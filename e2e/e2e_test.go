// Unless explicitly stated otherwise all files in this repository are licensed under the Apache-2.0 License.
// This product includes software developed at Datadog (https://www.datadoghq.com/) Copyright 2026 Datadog, Inc.

package e2e

import (
	"context"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
	"time"

	run "cloud.google.com/go/run/apiv2"
	"github.com/gruntwork-io/terratest/modules/logger"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/require"

	e2eshared "github.com/DataDog/terraform-google-cloud-run-datadog/e2e/shared"
)

const (
	defaultProject = "datadog-serverless-gcp-dev"
	defaultRegion  = "us-central1"
	// Pin the sidecar so failures blame this module, not upstream serverless-init drift.
	defaultSidecarImage = "gcr.io/datadoghq/serverless-init@sha256:6fb7637628fdf31d536bc9c49fbe6304371df5e2ecdb15c1c2d5e2d66395c3a0"

	testEnv = "e2e"
	// The module mirrors datadog_version into a GCP label, which rejects '.',
	// so the version must be label-safe (lowercase, digits, '-', '_').
	testVersion = "1-0-0"

	nodeFunctionBaseImage = "us-central1-docker.pkg.dev/serverless-runtimes/google-22-full/runtimes/nodejs22"
)

type config struct {
	project      string
	region       string
	sidecarImage string
	site         string
	ddAPIKey     string
	ddAPPKey     string
}

// loadConfig reads the suite's shared inputs from the environment.
// Per-runtime workload images come from E2E_IMAGE_<RUNTIME>_<MODE> (see build_images.sh).
func loadConfig(t *testing.T) config {
	t.Helper()

	cfg := config{
		project:      firstNonEmpty(os.Getenv("GCP_PROJECT_ID"), defaultProject),
		region:       firstNonEmpty(os.Getenv("GCP_REGION"), defaultRegion),
		sidecarImage: firstNonEmpty(os.Getenv("DD_SIDECAR_IMAGE_E2E"), defaultSidecarImage),
		site:         firstNonEmpty(os.Getenv("DD_SITE"), "datadoghq.com"),
		ddAPIKey:     firstNonEmpty(os.Getenv("DATADOG_API_KEY"), os.Getenv("DD_API_KEY")),
		ddAPPKey:     firstNonEmpty(os.Getenv("DATADOG_APP_KEY"), os.Getenv("DD_APP_KEY")),
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

// scenario configures one Cloud Run e2e lifecycle variant for an examples runtime.
type scenario struct {
	name string
	// imageEnv is the env var holding the workload image (from build_images.sh).
	imageEnv string
	// isFunction enables Cloud Run Functions build_config + base_image_uri.
	isFunction bool
}

func runtimeScenarios() []scenario {
	return []scenario{
		{name: "go_sidecar", imageEnv: "E2E_IMAGE_GO_SIDECAR"},
		{
			name:     "node_sidecar",
			imageEnv: "E2E_IMAGE_NODE_SIDECAR",
		},
		{
			name:     "python_sidecar",
			imageEnv: "E2E_IMAGE_PYTHON_SIDECAR",
		},
		{
			name:     "ruby_sidecar",
			imageEnv: "E2E_IMAGE_RUBY_SIDECAR",
		},
		{
			name:     "php_sidecar",
			imageEnv: "E2E_IMAGE_PHP_SIDECAR",
		},
		{
			name:     "dotnet_sidecar",
			imageEnv: "E2E_IMAGE_DOTNET_SIDECAR",
		},
		{
			name:       "node_function_sidecar",
			imageEnv:   "E2E_IMAGE_NODE_FUNCTION_SIDECAR",
			isFunction: true,
		},
	}
}

// TestCloudRunE2E runs the full instrumentation lifecycle for every examples runtime.
func TestCloudRunE2E(t *testing.T) {
	cfg := loadConfig(t)

	for _, sc := range runtimeScenarios() {
		sc := sc
		t.Run(sc.name, func(t *testing.T) {
			t.Parallel()
			runCloudRunE2E(t, cfg, sc)
		})
	}
}

// runCloudRunE2E applies the module, verifies config, triggers and verifies telemetry,
// asserts re-apply is a no-op, then destroys and verifies no residue.
func runCloudRunE2E(t *testing.T, cfg config, sc scenario) {
	t.Helper()

	workloadImage := os.Getenv(sc.imageEnv)
	if workloadImage == "" {
		t.Fatalf("missing workload image env %s (run e2e/build_images.sh and source e2e/.image-env)", sc.imageEnv)
	}

	ctx := context.Background()
	cloudRun, err := run.NewServicesClient(ctx)
	require.NoError(t, err, "create Cloud Run client")
	defer cloudRun.Close()

	// one-e2e-tf-cloud-run-<runid>: identity + sweeper blast-radius guard. The freshness
	// timestamp is captured now, at creation time, and mirrored into a GCP label.
	runID := e2eshared.NewRunID()
	serviceName := e2eshared.ResourceName(sharedCfg, runID)
	createdTS := strconv.FormatInt(time.Now().Unix(), 10)
	t.Logf("run id %s -> service %s (scenario=%s)", runID, serviceName, sc.name)

	fixtureDir := prepareFixtureDir(t)

	vars := map[string]interface{}{
		"project":         cfg.project,
		"region":          cfg.region,
		"name":            serviceName,
		"workload_image":  workloadImage,
		"sidecar_image":   cfg.sidecarImage,
		"datadog_site":    cfg.site,
		"datadog_service": serviceName,
		"datadog_env":     testEnv,
		"datadog_version": testVersion,
		"run_id":          runID,
		"created_ts":      createdTS,
	}
	if sc.isFunction {
		vars["base_image_uri"] = nodeFunctionBaseImage
		vars["build_config"] = map[string]interface{}{
			"function_target":          "helloHttp",
			"image_uri":                workloadImage,
			"base_image":               nodeFunctionBaseImage,
			"enable_automatic_updates": true,
		}
	}

	tfOpts := &terraform.Options{
		TerraformDir: fixtureDir,
		Vars:         vars,
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

// prepareFixtureDir copies e2e/fixture into a unique temp dir and rewrites the
// module source to a path relative to that copy so parallel subtests do not
// share state. Terraform local module sources must start with ./ or ../;
// absolute paths are treated as remote packages and are not used here.
func prepareFixtureDir(t *testing.T) string {
	t.Helper()

	srcDir, err := filepath.Abs("fixture")
	require.NoError(t, err, "resolve fixture dir")
	moduleRoot, err := filepath.Abs("..")
	require.NoError(t, err, "resolve module root")

	dstDir := t.TempDir()
	relSource, err := filepath.Rel(dstDir, moduleRoot)
	require.NoError(t, err, "relative module source from fixture copy")
	relSource = filepath.ToSlash(relSource)
	switch {
	case relSource == ".":
		relSource = "./"
	case !strings.HasPrefix(relSource, "../") && !strings.HasPrefix(relSource, "./"):
		relSource = "./" + relSource
	}

	entries, err := os.ReadDir(srcDir)
	require.NoError(t, err, "read fixture dir")
	for _, ent := range entries {
		if ent.IsDir() {
			continue
		}
		name := ent.Name()
		srcPath := filepath.Join(srcDir, name)
		dstPath := filepath.Join(dstDir, name)
		data, err := os.ReadFile(srcPath)
		require.NoError(t, err, "read %s", srcPath)
		if name == "main.tf" {
			data = []byte(strings.Replace(
				string(data),
				`source              = "../../"`,
				`source              = "`+relSource+`"`,
				1,
			))
		}
		require.NoError(t, os.WriteFile(dstPath, data, 0o644), "write %s", dstPath)
	}

	return dstDir
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
	const bodyLimit = 512
	got2xx := false
	for attempt := 1; attempt <= attempts; attempt++ {
		resp, err := client.Get(uri)
		if err != nil {
			t.Logf("trigger attempt %d/%d: %v", attempt, attempts, err)
			time.Sleep(10 * time.Second)
			continue
		}
		body, _ := io.ReadAll(io.LimitReader(resp.Body, bodyLimit))
		resp.Body.Close()
		if resp.StatusCode >= 200 && resp.StatusCode < 300 {
			t.Logf("trigger attempt %d/%d: HTTP %d", attempt, attempts, resp.StatusCode)
			got2xx = true
			// A couple more hits to make sure spans/logs are emitted.
			if attempt >= 2 {
				break
			}
		} else {
			snippet := strings.TrimSpace(string(body))
			if snippet == "" {
				snippet = "<empty body>"
			}
			t.Logf("trigger attempt %d/%d: HTTP %d body=%q", attempt, attempts, resp.StatusCode, snippet)
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
