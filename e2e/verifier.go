// Unless explicitly stated otherwise all files in this repository are licensed under the Apache-2.0 License.
// This product includes software developed at Datadog (https://www.datadoghq.com/) Copyright 2026 Datadog, Inc.

package e2e

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"
	"time"

	e2eshared "github.com/DataDog/terraform-google-cloud-run-datadog/e2e/shared"
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

// These types mirror `gcloud run services describe --format=json`. gcloud may emit
// either the Cloud Run v2 shape (top-level template/labels) or the v1 knative shape
// (spec.template.spec / metadata.labels), so we model both and read whichever is
// populated.
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

type volume struct {
	Name string `json:"name"`
}

type template struct {
	Containers []container `json:"containers"`
	Volumes    []volume    `json:"volumes"`
}

type cloudRunService struct {
	// v2 shape
	Labels   map[string]string `json:"labels"`
	Template template          `json:"template"`
	// v1 knative shape
	Metadata struct {
		Labels map[string]string `json:"labels"`
	} `json:"metadata"`
	Spec struct {
		Template struct {
			Spec template `json:"spec"`
		} `json:"template"`
	} `json:"spec"`
}

// Expectations pins what an instrumented Cloud Run service must look like, so a mismatch
// blames the module wiring rather than upstream drift.
type Expectations struct {
	ServiceName string
	Env         string
	Version     string
	RunID       string
	Site        string
	CreatedTS   string
}

// getTemplate returns the service template from whichever API shape gcloud emitted.
func (s cloudRunService) getTemplate() template {
	if len(s.Template.Containers) > 0 {
		return s.Template
	}

	return s.Spec.Template.Spec
}

// getLabels returns the service-level labels from whichever shape is populated.
func (s cloudRunService) getLabels() map[string]string {
	if len(s.Labels) > 0 {
		return s.Labels
	}

	return s.Metadata.Labels
}

// envMap flattens a container's env vars into a map for the shared verification helpers.
func (c container) envMap() map[string]string {
	m := make(map[string]string, len(c.Env))
	for _, e := range c.Env {
		m[e.Name] = e.Value
	}

	return m
}

func (c container) hasMount(volumeName string) bool {
	for _, m := range c.VolumeMounts {
		if m.Name == volumeName {
			return true
		}
	}

	return false
}

// describeService fetches the service definition, retrying transient errors. It returns
// the parsed service, the raw command result (for clean-state inspection), and any error.
func describeService(ctx context.Context, serviceName, project, region string) (cloudRunService, e2eshared.Result, error) {
	res, err := e2eshared.RunWithRetries(ctx, sharedCfg, 3, 5*time.Second,
		"run", "services", "describe", serviceName,
		"--project", project, "--region", region, "--platform", "managed", "--format", "json")

	var svc cloudRunService
	if err == nil {
		if uerr := json.Unmarshal([]byte(res.Stdout), &svc); uerr != nil {
			return svc, res, fmt.Errorf("parsing gcloud describe JSON: %w", uerr)
		}
	}

	return svc, res, err
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
		if !strings.Contains(sidecar.Image, "serverless-init") {
			v.Addf("sidecar image %q does not run serverless-init", sidecar.Image)
		}

		// Shared volume present and mounted into the sidecar.
		if !hasVolume(tmpl.Volumes, sharedVolumeName) {
			v.Addf("shared volume %q missing", sharedVolumeName)
		}
		if !sidecar.hasMount(sharedVolumeName) {
			v.Addf("sidecar does not mount shared volume %q", sharedVolumeName)
		}

		// API-key wiring + identity env vars live on the sidecar (the agent).
		sidecarEnv := sidecar.envMap()
		e2eshared.RequirePresent(&v, "sidecar env var", sidecarEnv, "DD_API_KEY", "DD_HEALTH_PORT")
		e2eshared.RequireValues(&v, "sidecar env var", sidecarEnv, map[string]string{
			"DD_SITE":    exp.Site,
			"DD_SERVICE": exp.ServiceName,
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
		e2eshared.RequirePresent(&v, fmt.Sprintf("app container %q env var", c.Name), appEnv,
			"DD_LOGS_INJECTION", "DD_SERVERLESS_LOG_PATH")
		e2eshared.RequireValues(&v, fmt.Sprintf("app container %q env var", c.Name), appEnv, map[string]string{
			"DD_SERVICE": exp.ServiceName,
			"DD_ENV":     exp.Env,
			"DD_VERSION": exp.Version,
		})
		if !c.hasMount(sharedVolumeName) {
			v.Addf("app container %q does not mount shared volume %q", c.Name, sharedVolumeName)
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

// verifyClean asserts the REMOVE step left no residue: the service -- and with it the
// sidecar, shared volume, and every DD_* env var and DD label -- is gone. describeService
// is expected to have failed (the service no longer exists); we confirm the failure is a
// not-found, not some transient error masquerading as success.
func verifyClean(res e2eshared.Result, describeErr error) error {
	var v e2eshared.Violations

	if describeErr == nil && res.ExitCode == 0 {
		v.Addf("service still exists after destroy")

		return v.Err("uninstrumented (post-remove) contract violated")
	}

	combined := res.Stdout + res.Stderr
	notFound := []string{"Cannot find service", "NOT_FOUND", "could not be found", "does not exist"}
	matched := false
	for _, phrase := range notFound {
		if strings.Contains(combined, phrase) {
			matched = true

			break
		}
	}
	if !matched {
		v.Addf("describe should report the service is gone, got: %s", combined)
	}

	return v.Err("uninstrumented (post-remove) contract violated")
}

func hasVolume(volumes []volume, name string) bool {
	for _, vol := range volumes {
		if vol.Name == name {
			return true
		}
	}

	return false
}
