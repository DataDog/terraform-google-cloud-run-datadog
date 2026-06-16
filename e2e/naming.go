// Unless explicitly stated otherwise all files in this repository are licensed under the Apache-2.0 License.
// This product includes software developed at Datadog (https://www.datadoghq.com/) Copyright 2026 Datadog, Inc.

package e2e

import (
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"strconv"
	"time"
)

// Resource hygiene convention shared across all serverless e2e suites: every
// resource is named one-e2e-<tool>-<platform>-<runid> and tagged with a
// one_e2e_created:<unix-ts> freshness marker set at creation. The cross-repo
// sweeper lists one-e2e- resources and deletes any whose freshness marker is
// outside the grace window (or unreadable), so the prefix is both an identity
// and a blast-radius guard.
const (
	hygienePrefix = "one-e2e"
	tool          = "tf"
	platform      = "cloud-run"

	// freshnessLabel is the GCP label key carrying the creation timestamp.
	// Label keys cannot contain ':', so the spec's one_e2e_created:<ts> tag is
	// expressed as the key=value label one_e2e_created=<ts>.
	freshnessLabel = "one_e2e_created"

	// runIDTag is the Datadog tag carrying the unique run marker, so ingested
	// telemetry can be filtered down to a single run.
	runIDTag = "one_e2e_run_id"
)

// run carries the identity of a single e2e execution: the random run id, the
// resource name derived from it, and the freshness timestamp.
type run struct {
	id          string
	serviceName string
	createdTS   string
}

// newRun mints a fresh run identity. The run id is 8 hex chars of crypto
// randomness (matching the reference impl) and the freshness timestamp is
// stamped now, at creation time.
func newRun() (run, error) {
	b := make([]byte, 4)
	if _, err := rand.Read(b); err != nil {
		return run{}, fmt.Errorf("generating run id: %w", err)
	}
	id := hex.EncodeToString(b)

	return run{
		id:          id,
		serviceName: fmt.Sprintf("%s-%s-%s-%s", hygienePrefix, tool, platform, id),
		createdTS:   strconv.FormatInt(time.Now().Unix(), 10),
	}, nil
}
