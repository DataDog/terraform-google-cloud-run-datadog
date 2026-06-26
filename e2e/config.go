// Unless explicitly stated otherwise all files in this repository are licensed under the Apache-2.0 License.
// This product includes software developed at Datadog (https://www.datadoghq.com/) Copyright 2026 Datadog, Inc.

// Repo-local config for the Cloud Run e2e suite. The generic, cross-cloud helpers
// (exec/retry, telemetry polling, naming, verification primitives) come from the shared
// e2eshared package; what lives in this repo is everything Cloud-Run-specific: the GCP
// retry patterns, the sidecar/volume/env assertions, and the reduced telemetry identity.
package e2e

import (
	e2eshared "github.com/DataDog/terraform-google-cloud-run-datadog/e2e/shared"
)

// sharedCfg parameterizes the shared helpers for this module: the gcloud CLI, the GCP
// transient-error patterns safe to retry, and the tool/platform naming. The freshness
// and run-id tag keys default to the shared spec values (one_e2e_created / one_e2e_run_id),
// which the module mirrors into GCP labels and Datadog tags respectively.
var sharedCfg = e2eshared.Config{
	Tool:     "tf",
	Platform: "cloud-run",
	Command:  "gcloud",
	RetryPatterns: []string{
		"UNAVAILABLE",
		"ABORTED",
		"DEADLINE_EXCEEDED",
		"INTERNAL",
		"RESOURCE_EXHAUSTED",
		"TooManyRequests",
		"Conflict",
		"ETIMEDOUT",
		"ECONNRESET",
		"temporarily unavailable",
		"Operation was canceled",
		"could not refresh",
	},
}
