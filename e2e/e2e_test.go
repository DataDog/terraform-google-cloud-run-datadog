// Unless explicitly stated otherwise all files in this repository are licensed under the Apache-2.0 License.
// This product includes software developed at Datadog (https://www.datadoghq.com/) Copyright 2026 Datadog, Inc.

package e2e

import (
	"context"
	"net/http"
	"os"
	"strconv"
	"testing"
	"time"

	run "cloud.google.com/go/run/apiv2"
	"github.com/gruntwork-io/terratest/modules/logger"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/require"

	e2eshared "github.com/DataDog/terraform-google-cloud-run-datadog/e2e/shared"
)

// Pinned artifacts. Failures should blame this module, not upstream drift, so
// the workload app and the serverless-init sidecar are pinned by digest. CI may
// override the workload image via GCP_CLOUD_RUN_APP_IMAGE_E2E.
const (
	defaultProject       = "datadog-serverless-gcp-dev"
	defaultRegion        = "us-central1"
	defaultWorkloadImage = "gcr.io/datadog-serverless-gcp-dev/run-nodejs-sidecar@sha256:010d0e9990ac1bb8874322f9a6795f0833c9267d40f9a2b9e9779980bba5ba19"
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

// loadConfig reads the suite's required inputs from the environment.
func loadConfig(t *testing.T) config {
	t.Helper()

	cfg := config{
		project:       firstNonEmpty(os.Getenv("GCP_PROJECT_ID"), defaultProject),
		region:        firstNonEmpty(os.Getenv("GCP_REGION"), defaultRegion),
		workloadImage: firstNonEmpty(os.Getenv("GCP_CLOUD_RUN_APP_IMAGE_E2E"), defaultWorkloadImage),
		sidecarImage:  firstNonEmpty(os.Getenv("DD_SIDECAR_IMAGE_E2E"), defaultSidecarImage),
		site:          firstNonEmpty(os.Getenv("DD_SITE"), "datadoghq.com"),
		ddAPIKey:      firstNonEmpty(os.Getenv("DATADOG_API_KEY"), os.Getenv("DD_API_KEY")),
		ddAPPKey:      firstNonEmpty(os.Getenv("DATADOG_APP_KEY"), os.Getenv("DD_APP_KEY")),
	}

	missing := []string{}
	for name, val := range map[string]string{
		"DATADOG_API_KEY/DD_API_KEY": cfg.ddAPIKey,
		"DATADOG_APP_KEY/DD_APP_KEY": cfg.ddAPPKey,
	} {
		if val == "" {
			missing = append(missing, name)
		}
	}
	if len(missing) > 0 {
		t.Fatalf("missing required env for e2e: %v", missing)
	}

	return cfg
}

// TestCloudRunE2E runs the full instrumentation lifecycle against a live,
// ephemeral Cloud Run service: APPLY the module (which both provisions the
// workload and instruments it), verify config, trigger and verify telemetry,
// assert re-apply is a no-op, then destroy and verify no residue.
func TestCloudRunE2E(t *testing.T) {
	cfg := loadConfig(t)
	ctx := context.Background()
	cloudRun, err := run.NewServicesClient(ctx)
	require.NoError(t, err, "create Cloud Run client")
	defer cloudRun.Close()

	// one-e2e-tf-cloud-run-<runid>: identity + sweeper blast-radius guard. The freshness
	// timestamp is captured now, at creation time, and mirrored into a GCP label.
	runID := e2eshared.NewRunID()
	serviceName := e2eshared.ResourceName(sharedCfg, runID)
	createdTS := strconv.FormatInt(time.Now().Unix(), 10)
	t.Logf("run id %s -> service %s", runID, serviceName)

	tfOpts := &terraform.Options{
		TerraformDir: "fixture",
		Vars: map[string]interface{}{
			"project":         cfg.project,
			"region":          cfg.region,
			"name":            serviceName,
			"workload_image":  cfg.workloadImage,
			"sidecar_image":   cfg.sidecarImage,
			"datadog_site":    cfg.site,
			"datadog_service": serviceName,
			"datadog_env":     testEnv,
			"datadog_version": testVersion,
			"run_id":          runID,
			"created_ts":      createdTS,
		},
		// Pass secrets by environment so Terratest never prints them as CLI arguments.
		EnvVars: map[string]string{
			"TF_VAR_datadog_api_key": cfg.ddAPIKey,
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
		Logger:             logger.Discard,
	}

	// Teardown always, even on failure. This is a safety net; the asserted
	// REMOVE step below destroys first, leaving this a no-op on success.
	defer terraform.Destroy(t, tfOpts)

	exp := Expectations{
		ServiceName:  serviceName,
		Env:          testEnv,
		Version:      testVersion,
		RunID:        runID,
		Site:         cfg.site,
		SidecarImage: cfg.sidecarImage,
		CreatedTS:    createdTS,
	}

	// APPLY -> verify CONFIG.
	func() {
		done := logProgress(t, "applying the Cloud Run service")
		defer done()
		terraform.InitAndApply(t, tfOpts)
	}()
	func() {
		done := logProgress(t, "verifying the deployed configuration")
		defer done()
		svc, err := describeService(ctx, cloudRun, serviceName, cfg.project, cfg.region)
		require.NoError(t, err, "describe instrumented service")
		require.NoError(t, verifyInstrumented(svc, exp))
	}()

	// Trigger workload -> verify TELEMETRY flows.
	uri := terraform.Output(t, tfOpts, "service_uri")
	require.NotEmpty(t, uri, "service URI output")
	func() {
		done := logProgress(t, "triggering the workload")
		defer done()
		triggerWorkload(t, uri)
	}()
	client := e2eshared.NewTelemetryClient(cfg.site, cfg.ddAPIKey, cfg.ddAPPKey)
	telemetryCtx, cancel := context.WithTimeout(ctx, 12*time.Minute)
	defer cancel()
	func() {
		done := logProgress(t, "waiting for Datadog telemetry")
		defer done()
		require.NoError(t, checkTelemetryFlowing(telemetryCtx, t, client, serviceName, runID, testEnv, uri))
	}()

	// Re-APPLY -> assert idempotent (no diff, no duplicate).
	func() {
		done := logProgress(t, "checking Terraform idempotence")
		defer done()
		exitCode := terraform.PlanExitCode(t, tfOpts)
		require.Equal(t, 0, exitCode, "re-apply must be a no-op: terraform plan reported a diff")
	}()

	// REMOVE -> verify CLEAN end-state.
	func() {
		done := logProgress(t, "removing the Cloud Run service")
		defer done()
		terraform.Destroy(t, tfOpts)
	}()
	func() {
		done := logProgress(t, "verifying cleanup")
		defer done()
		_, describeErr := describeService(ctx, cloudRun, serviceName, cfg.project, cfg.region)
		require.NoError(t, verifyClean(describeErr))
	}()
}

// logProgress reports phase boundaries and emits a heartbeat while a phase is running.
func logProgress(t *testing.T, phase string) func() {
	t.Helper()
	started := time.Now()
	t.Logf("START: %s", phase)

	stop := make(chan struct{})
	done := make(chan struct{})
	go func() {
		defer close(done)
		ticker := time.NewTicker(30 * time.Second)
		defer ticker.Stop()
		for {
			select {
			case <-ticker.C:
				t.Logf("RUNNING: %s (%s elapsed)", phase, time.Since(started).Round(time.Second))
			case <-stop:
				return
			}
		}
	}()

	return func() {
		close(stop)
		<-done
		t.Logf("DONE: %s (%s)", phase, time.Since(started).Round(time.Second))
	}
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
