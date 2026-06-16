// Unless explicitly stated otherwise all files in this repository are licensed under the Apache-2.0 License.
// This product includes software developed at Datadog (https://www.datadoghq.com/) Copyright 2026 Datadog, Inc.

package e2e

import (
	"net/http"
	"os"
	"testing"
	"time"

	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/require"
)

// Pinned artifacts. Failures should blame this module, not upstream drift, so
// the workload app and the serverless-init sidecar are pinned by digest. CI may
// override the workload image via GCP_CLOUD_RUN_APP_IMAGE_E2E.
const (
	defaultWorkloadImage = "gcr.io/dd-dev-serverless-selfmonitor/self-monitoring-cloud-run-node-sidecar-prod@sha256:af6be6d911d4b6a51efae6022fab6522d39247199b5a4f7923e302128921dfd0"
	defaultSidecarImage  = "gcr.io/datadoghq/serverless-init@sha256:6fb7637628fdf31d536bc9c49fbe6304371df5e2ecdb15c1c2d5e2d66395c3a0"

	// One canonical runtime; exhaustiveness across runtimes lives upstream.
	testEnv = "e2e"
	// The module mirrors datadog_version into a GCP label, which rejects '.',
	// so the version must be label-safe (lowercase, digits, '-', '_').
	testVersion = "1-0-0"
)

type config struct {
	project       string
	region        string
	workloadImage string
	sidecarImage  string
	site          string
	ddAPIKey      string
	ddAPPKey      string
}

// loadConfig reads the suite's inputs from the environment, skipping (not
// failing) when the suite is disabled or required inputs are absent -- so CI
// stays green before OIDC/secrets are wired, and local runs get a clear skip.
func loadConfig(t *testing.T) config {
	t.Helper()
	if os.Getenv("SKIP_CLOUD_RUN_TESTS") == "true" {
		t.Skip("SKIP_CLOUD_RUN_TESTS=true")
	}

	cfg := config{
		project:       os.Getenv("GCP_PROJECT_ID"),
		region:        os.Getenv("GCP_REGION"),
		workloadImage: firstNonEmpty(os.Getenv("GCP_CLOUD_RUN_APP_IMAGE_E2E"), defaultWorkloadImage),
		sidecarImage:  firstNonEmpty(os.Getenv("DD_SIDECAR_IMAGE_E2E"), defaultSidecarImage),
		site:          firstNonEmpty(os.Getenv("DD_SITE"), "datadoghq.com"),
		ddAPIKey:      firstNonEmpty(os.Getenv("DATADOG_API_KEY"), os.Getenv("DD_API_KEY")),
		ddAPPKey:      firstNonEmpty(os.Getenv("DATADOG_APP_KEY"), os.Getenv("DD_APP_KEY")),
	}

	missing := []string{}
	for name, val := range map[string]string{
		"GCP_PROJECT_ID":             cfg.project,
		"GCP_REGION":                 cfg.region,
		"DATADOG_API_KEY/DD_API_KEY": cfg.ddAPIKey,
		"DATADOG_APP_KEY/DD_APP_KEY": cfg.ddAPPKey,
	} {
		if val == "" {
			missing = append(missing, name)
		}
	}
	if len(missing) > 0 {
		t.Skipf("missing required env for e2e: %v", missing)
	}

	return cfg
}

// TestCloudRunE2E runs the full instrumentation lifecycle against a live,
// ephemeral Cloud Run service: APPLY the module (which both provisions the
// workload and instruments it), verify config, trigger and verify telemetry,
// assert re-apply is a no-op, then destroy and verify no residue.
func TestCloudRunE2E(t *testing.T) {
	cfg := loadConfig(t)

	r, err := newRun()
	require.NoError(t, err)
	t.Logf("run id %s -> service %s", r.id, r.serviceName)

	tfOpts := &terraform.Options{
		TerraformDir: "fixture",
		Vars: map[string]interface{}{
			"project":         cfg.project,
			"region":          cfg.region,
			"name":            r.serviceName,
			"workload_image":  cfg.workloadImage,
			"sidecar_image":   cfg.sidecarImage,
			"datadog_api_key": cfg.ddAPIKey,
			"datadog_site":    cfg.site,
			"datadog_service": r.serviceName,
			"datadog_env":     testEnv,
			"datadog_version": testVersion,
			"run_id":          r.id,
			"created_ts":      r.createdTS,
		},
		// Retry the cloud, not the assertions: bounded retries on transient
		// control-plane errors only.
		RetryableTerraformErrors: map[string]string{
			".*UNAVAILABLE.*":           "transient Cloud Run API unavailability",
			".*RESOURCE_EXHAUSTED.*":    "transient quota/throttling",
			".*DEADLINE_EXCEEDED.*":     "transient control-plane timeout",
			".*Error 429.*":             "transient throttling",
			".*Error 50[0-9].*":         "transient server error",
			".*connection reset.*":      "transient network error",
			".*TLS handshake timeout.*": "transient network error",
		},
		MaxRetries:         3,
		TimeBetweenRetries: 10 * time.Second,
		NoColor:            true,
	}

	// Teardown always, even on failure. This is a safety net; the asserted
	// REMOVE step below destroys first, leaving this a no-op on success.
	defer terraform.Destroy(t, tfOpts)

	// APPLY -> verify CONFIG.
	terraform.InitAndApply(t, tfOpts)
	verifyInstrumented(t, r, cfg.project, cfg.region, cfg.site, testEnv, testVersion)

	// Trigger workload -> verify TELEMETRY flows.
	uri := terraform.Output(t, tfOpts, "service_uri")
	require.NotEmpty(t, uri, "service URI output")
	triggerWorkload(t, uri)
	checkTelemetryFlowing(t, telemetryConfig{apiKey: cfg.ddAPIKey, appKey: cfg.ddAPPKey, site: cfg.site}, r, testEnv)

	// Re-APPLY -> assert idempotent (no diff, no duplicate).
	exitCode := terraform.PlanExitCode(t, tfOpts)
	require.Equal(t, 0, exitCode, "re-apply must be a no-op: terraform plan reported a diff")

	// REMOVE -> verify CLEAN end-state.
	terraform.Destroy(t, tfOpts)
	verifyClean(t, r, cfg.project, cfg.region)
}

// triggerWorkload issues HTTP GETs against the service to drive a log line and
// a trace, retrying through cold starts on a bounded budget.
func triggerWorkload(t *testing.T, uri string) {
	t.Helper()
	client := &http.Client{Timeout: 30 * time.Second}
	const attempts = 10
	got2xx := false
	for attempt := 1; attempt <= attempts; attempt++ {
		resp, err := client.Get(uri)
		if err != nil {
			t.Logf("trigger attempt %d/%d: %v", attempt, attempts, err)
			time.Sleep(10 * time.Second)
			continue
		}
		resp.Body.Close()
		t.Logf("trigger attempt %d/%d: HTTP %d", attempt, attempts, resp.StatusCode)
		if resp.StatusCode >= 200 && resp.StatusCode < 300 {
			got2xx = true
			// A couple more hits to make sure spans/logs are emitted.
			if attempt >= 2 {
				break
			}
		}
		time.Sleep(5 * time.Second)
	}
	require.True(t, got2xx, "workload did not return a 2xx response within budget")
}

func firstNonEmpty(vals ...string) string {
	for _, v := range vals {
		if v != "" {
			return v
		}
	}

	return ""
}
