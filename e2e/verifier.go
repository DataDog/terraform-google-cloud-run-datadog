// Unless explicitly stated otherwise all files in this repository are licensed under the Apache-2.0 License.
// This product includes software developed at Datadog (https://www.datadoghq.com/) Copyright 2026 Datadog, Inc.

package e2e

import (
	"context"
	"encoding/json"
	"fmt"

	run "cloud.google.com/go/run/apiv2"
	runpb "cloud.google.com/go/run/apiv2/runpb"
	e2eshared "github.com/DataDog/terraform-google-cloud-run-datadog/e2e/shared"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
	"google.golang.org/protobuf/encoding/protojson"
)

// Names the module assigns to the components it injects.
const (
	sidecarName      = "datadog-sidecar"
	sharedVolumeName = "shared-volume"

	// freshnessLabel is the GCP label key carrying the creation timestamp. Label keys
	// cannot contain ':', so the spec's one_e2e_created:<ts> tag is expressed as the
	// key=value label one_e2e_created=<ts>. It mirrors the shared freshness tag key.
	freshnessLabel = e2eshared.DefaultFreshnessTagKey
)

// These types mirror the Cloud Run v2 API response after protojson conversion.
type envVar struct {
	Name  string `json:"name"`
	Value string `json:"value"`
}

type volumeMount struct {
	Name      string `json:"name"`
	MountPath string `json:"mountPath"`
}

type container struct {
	Name         string        `json:"name"`
	Image        string        `json:"image"`
	Env          []envVar      `json:"env"`
	VolumeMounts []volumeMount `json:"volumeMounts"`
}

type emptyDir struct {
	Medium    string `json:"medium"`
	SizeLimit string `json:"sizeLimit"`
}

type volume struct {
	Name     string    `json:"name"`
	EmptyDir *emptyDir `json:"emptyDir"`
}

type template struct {
	Containers []container `json:"containers"`
	Volumes    []volume    `json:"volumes"`
}

type cloudRunService struct {
	Labels   map[string]string `json:"labels"`
	Template template          `json:"template"`
}

// Expectations pins what an instrumented Cloud Run service must look like, so a mismatch
// blames the module wiring rather than upstream drift.
type Expectations struct {
	ServiceName  string
	Env          string
	Version      string
	RunID        string
	Site         string
	SidecarImage string
	CreatedTS    string
}

func (s cloudRunService) getTemplate() template {
	return s.Template
}

func (s cloudRunService) getLabels() map[string]string {
	return s.Labels
}

// envMap flattens a container's env vars into a map for the shared verification helpers.
func (c container) envMap() map[string]string {
	m := make(map[string]string, len(c.Env))
	for _, e := range c.Env {
		m[e.Name] = e.Value
	}

	return m
}

func (c container) hasMount(volumeName, mountPath string) bool {
	for _, m := range c.VolumeMounts {
		if m.Name == volumeName && m.MountPath == mountPath {
			return true
		}
	}

	return false
}

// describeService fetches the service through the Cloud Run API using Application
// Default Credentials, then converts the response into the verifier's compact shape.
func describeService(ctx context.Context, client *run.ServicesClient, serviceName, project, region string) (cloudRunService, error) {
	name := fmt.Sprintf("projects/%s/locations/%s/services/%s", project, region, serviceName)
	service, err := client.GetService(ctx, &runpb.GetServiceRequest{Name: name})
	if err != nil {
		return cloudRunService{}, fmt.Errorf("get Cloud Run service %q: %w", name, err)
	}

	raw, err := protojson.Marshal(service)
	if err != nil {
		return cloudRunService{}, fmt.Errorf("marshal Cloud Run service %q: %w", name, err)
	}

	var parsed cloudRunService
	if err := json.Unmarshal(raw, &parsed); err != nil {
		return cloudRunService{}, fmt.Errorf("parse Cloud Run service %q: %w", name, err)
	}

	return parsed, nil
}

// verifyInstrumented asserts the module produced a correctly instrumented service: the
// sidecar + shared volume + mounts are present, the wiring env vars are set, and the
// identifying labels hold the expected *values* (identity, not mere existence).
func verifyInstrumented(svc cloudRunService, exp Expectations) error {
	var v e2eshared.Violations

	tmpl := svc.getTemplate()
	containers := tmpl.Containers
	if len(containers) == 0 {
		v.Addf("service has no containers")

		return v.Err("instrumented contract violated")
	}

	// Sidecar: present and running the pinned serverless-init image.
	var sidecar *container
	for i := range containers {
		if containers[i].Name == sidecarName {
			sidecar = &containers[i]
		}
	}
	if sidecar == nil {
		v.Addf("datadog-sidecar container missing")
	} else {
		if sidecar.Image != exp.SidecarImage {
			v.Addf("sidecar image = %q, want pinned image %q", sidecar.Image, exp.SidecarImage)
		}

		// The module-owned volume must retain its expected in-memory configuration.
		sharedVolume, ok := findVolume(tmpl.Volumes, sharedVolumeName)
		if !ok {
			v.Addf("shared volume %q missing", sharedVolumeName)
		} else if sharedVolume.EmptyDir == nil {
			v.Addf("shared volume %q is not an emptyDir volume", sharedVolumeName)
		} else {
			if sharedVolume.EmptyDir.Medium != "MEMORY" {
				v.Addf("shared volume medium = %q, want MEMORY", sharedVolume.EmptyDir.Medium)
			}
			if sharedVolume.EmptyDir.SizeLimit != "" {
				v.Addf("shared volume size limit = %q, want unset", sharedVolume.EmptyDir.SizeLimit)
			}
		}
		if !sidecar.hasMount(sharedVolumeName, "/shared-volume") {
			v.Addf("sidecar does not mount shared volume %q at /shared-volume", sharedVolumeName)
		}

		// API-key wiring + identity env vars live on the sidecar (the agent).
		sidecarEnv := sidecar.envMap()
		e2eshared.RequirePresent(&v, "sidecar env var", sidecarEnv, "DD_API_KEY")
		e2eshared.RequireValues(&v, "sidecar env var", sidecarEnv, map[string]string{
			"DD_SITE":                exp.Site,
			"DD_SERVICE":             exp.ServiceName,
			"DD_ENV":                 exp.Env,
			"DD_VERSION":             exp.Version,
			"DD_TAGS":                e2eshared.DefaultRunIDTagKey + ":" + exp.RunID,
			"DD_HEALTH_PORT":         "5555",
			"DD_SERVERLESS_LOG_PATH": "/shared-volume/logs/*.log",
		})
	}

	// App containers: log-injection + identity env vars, plus the log volume.
	appContainers := 0
	for _, c := range containers {
		if c.Name == sidecarName {
			continue
		}
		appContainers++
		appEnv := c.envMap()
		e2eshared.RequireValues(&v, fmt.Sprintf("app container %q env var", c.Name), appEnv, map[string]string{
			"DD_SERVICE":             exp.ServiceName,
			"DD_ENV":                 exp.Env,
			"DD_VERSION":             exp.Version,
			"DD_LOGS_INJECTION":      "true",
			"DD_SERVERLESS_LOG_PATH": "/shared-volume/logs/*.log",
		})
		if !c.hasMount(sharedVolumeName, "/shared-volume") {
			v.Addf("app container %q does not mount shared volume %q at /shared-volume", c.Name, sharedVolumeName)
		}
	}
	if appContainers == 0 {
		v.Addf("service has no app containers")
	}

	// Identifying labels carry the expected values. version is mirrored into a label
	// (label-safe form) even though it is not reliably stamped on spans.
	labels := svc.getLabels()
	e2eshared.RequireValues(&v, "label", labels, map[string]string{
		"service":      exp.ServiceName,
		"env":          exp.Env,
		"version":      exp.Version,
		freshnessLabel: exp.CreatedTS,
	})
	if labels["dd_sls_terraform_module"] == "" {
		v.Addf("missing dd_sls_terraform_module module marker label")
	}

	return v.Err("instrumented contract violated")
}

// verifyClean asserts that the Cloud Run API reports the service as deleted, rather
// than accepting an unrelated authentication or transient failure as successful cleanup.
func verifyClean(describeErr error) error {
	var v e2eshared.Violations

	if describeErr == nil {
		v.Addf("service still exists after destroy")
	} else if status.Code(describeErr) != codes.NotFound {
		v.Addf("get service after destroy: want NotFound, got %v", describeErr)
	}

	return v.Err("uninstrumented (post-remove) contract violated")
}

func findVolume(volumes []volume, name string) (volume, bool) {
	for _, vol := range volumes {
		if vol.Name == name {
			return vol, true
		}
	}

	return volume{}, false
}
