// Unless explicitly stated otherwise all files in this repository are licensed under the Apache-2.0 License.
// This product includes software developed at Datadog (https://www.datadoghq.com/) Copyright 2026 Datadog, Inc.

package e2e

import (
	"encoding/json"
	"strings"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// Names the module assigns to the components it injects.
const (
	sidecarName      = "datadog-sidecar"
	sharedVolumeName = "shared-volume"
)

// These types mirror `gcloud run services describe --format=json`. gcloud may
// emit either the Cloud Run v2 shape (top-level template/labels) or the v1
// knative shape (spec.template.spec / metadata.labels), so -- like the
// reference verifier -- we model both and read whichever is populated.
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

// getTemplate returns the service template from whichever API shape gcloud
// emitted.
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

// describeService fetches the service definition, retrying transient errors.
func describeService(t *testing.T, serviceName, project, region string) (cloudRunService, commandResult) {
	t.Helper()
	res := runWithRetries(3, 5*time.Second, "gcloud", "run", "services", "describe", serviceName,
		"--project", project, "--region", region, "--platform", "managed", "--format", "json")

	var svc cloudRunService
	if res.exitCode == 0 {
		require.NoError(t, json.Unmarshal([]byte(res.stdout), &svc), "parsing gcloud describe JSON")
	}

	return svc, res
}

func (c container) envValue(name string) (string, bool) {
	for _, e := range c.Env {
		if e.Name == name {
			return e.Value, true
		}
	}

	return "", false
}

func (c container) hasMount(volumeName string) bool {
	for _, m := range c.VolumeMounts {
		if m.Name == volumeName {
			return true
		}
	}

	return false
}

// verifyInstrumented asserts the module produced a correctly instrumented
// service: the sidecar + shared volume + mounts are present, the wiring env
// vars are set, and the identifying tags hold the expected *values* (identity,
// not mere existence).
func verifyInstrumented(t *testing.T, r run, project, region, site, env, version string) {
	t.Helper()
	svc, res := describeService(t, r.serviceName, project, region)
	require.Equal(t, 0, res.exitCode, "describe instrumented service: %s", res.stderr)

	tmpl := svc.getTemplate()
	containers := tmpl.Containers
	require.NotEmpty(t, containers, "service has containers")

	// Sidecar: present and running the pinned serverless-init image.
	var sidecar *container
	for i := range containers {
		if containers[i].Name == sidecarName {
			sidecar = &containers[i]
		}
	}
	require.NotNil(t, sidecar, "datadog-sidecar container present")
	assert.Contains(t, sidecar.Image, "serverless-init", "sidecar runs serverless-init")

	// Shared volume present and mounted into the sidecar.
	assert.True(t, hasVolume(tmpl.Volumes, sharedVolumeName), "shared volume present")
	assert.True(t, sidecar.hasMount(sharedVolumeName), "sidecar mounts shared volume")

	// API-key wiring + identity env vars live on the sidecar (the agent).
	assertEnvPresent(t, *sidecar, "DD_API_KEY", "DD_SITE", "DD_SERVICE", "DD_HEALTH_PORT")
	assertEnvEquals(t, *sidecar, "DD_SITE", site)
	assertEnvEquals(t, *sidecar, "DD_SERVICE", r.serviceName)

	// App containers: log-injection + identity env vars, plus the log volume.
	appContainers := 0
	for _, c := range containers {
		if c.Name == sidecarName {
			continue
		}
		appContainers++
		assertEnvPresent(t, c, "DD_SERVICE", "DD_LOGS_INJECTION", "DD_SERVERLESS_LOG_PATH")
		assertEnvEquals(t, c, "DD_SERVICE", r.serviceName)
		assertEnvEquals(t, c, "DD_ENV", env)
		assertEnvEquals(t, c, "DD_VERSION", version)
		assert.True(t, c.hasMount(sharedVolumeName), "app container %q mounts shared volume", c.Name)
	}
	require.Positive(t, appContainers, "service has at least one app container")

	// Identifying labels carry the expected values.
	labels := svc.getLabels()
	assert.Equal(t, r.serviceName, labels["service"], "service label")
	assert.Equal(t, env, labels["env"], "env label")
	assert.Equal(t, version, labels["version"], "version label")
	assert.Equal(t, r.createdTS, labels[freshnessLabel], "freshness label")
	assert.Contains(t, labels, "dd_sls_terraform_module", "module marker label")
}

// verifyClean asserts the REMOVE step left no residue: the service -- and with
// it the sidecar, shared volume, and every DD_* env var and DD label -- is gone.
func verifyClean(t *testing.T, r run, project, region string) {
	t.Helper()
	_, res := describeService(t, r.serviceName, project, region)
	require.NotEqual(t, 0, res.exitCode, "service should no longer exist after destroy")
	combined := res.stdout + res.stderr
	notFound := []string{"Cannot find service", "NOT_FOUND", "could not be found", "does not exist"}
	matched := false
	for _, phrase := range notFound {
		if strings.Contains(combined, phrase) {
			matched = true

			break
		}
	}
	assert.True(t, matched, "describe should report the service is gone, got: %s", combined)
}

func hasVolume(volumes []volume, name string) bool {
	for _, v := range volumes {
		if v.Name == name {
			return true
		}
	}

	return false
}

func assertEnvPresent(t *testing.T, c container, names ...string) {
	t.Helper()
	for _, n := range names {
		_, ok := c.envValue(n)
		assert.True(t, ok, "container %q has env var %s", c.Name, n)
	}
}

func assertEnvEquals(t *testing.T, c container, name, want string) {
	t.Helper()
	got, ok := c.envValue(name)
	if assert.True(t, ok, "container %q has env var %s", c.Name, name) {
		assert.Equal(t, want, got, "container %q env %s value", c.Name, name)
	}
}
