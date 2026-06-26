// Unless explicitly stated otherwise all files in this repository are licensed under the Apache-2.0 License.
// This product includes software developed at Datadog (https://www.datadoghq.com/) Copyright 2026 Datadog, Inc.

package e2e

import (
	"context"
	"fmt"
	"strings"
	"time"

	e2eshared "github.com/DataDog/terraform-google-cloud-run-datadog/e2e/shared"
)

// checkTelemetryFlowing polls spans and logs in parallel until each surfaces an event
// matching this run's identity, or the budget is exhausted. It runs on the shared
// TelemetryClient search primitives but keeps a Cloud-Run-specific match: identity is
// service + env + run-id marker, deliberately WITHOUT version. The tracer does not
// reliably stamp version on spans (upstream behaviour), so version is asserted in the
// config check (the GCP label) rather than on telemetry; using the shared
// SpanQuery/LogQuery/Identity here would over-assert.
//
// The workload is exercised continuously for the duration of the poll. The
// serverless-init sidecar tails the app's log file from the end (the right choice for
// ephemeral runtimes, so a restart never replays stale logs), so only lines written
// after the sidecar attaches its tailer are forwarded. The app boots faster than the
// agent, so the lines emitted by the up-front trigger already sit behind the tail offset
// and never ship; without fresh traffic the logs assertion times out even though logging
// is wired correctly. Spans don't need this -- the tracer pushes them over HTTP
// immediately, independent of any file offset.
func checkTelemetryFlowing(ctx context.Context, client *e2eshared.TelemetryClient, serviceName, runID, env, uri string) error {
	tctx, stopTraffic := context.WithCancel(ctx)
	defer stopTraffic()
	go e2eshared.GenerateTraffic(tctx, uri, 5*time.Second)

	// service + env + run-id marker, no version (see doc comment).
	query := fmt.Sprintf("service:%s env:%s %s:%s", serviceName, env, e2eshared.DefaultRunIDTagKey, runID)
	match := func(e e2eshared.Event) bool {
		return e.Has("service", serviceName) &&
			e.Has("env", env) &&
			e.Has(e2eshared.DefaultRunIDTagKey, runID)
	}

	type result struct {
		label string
		err   error
	}
	results := make(chan result, 2)
	go func() {
		results <- result{"spans", pollUntilMatch(ctx, client, "spans", client.SearchSpans, query, match)}
	}()
	go func() {
		results <- result{"logs", pollUntilMatch(ctx, client, "logs", client.SearchLogs, query, match)}
	}()

	var errs []string
	for i := 0; i < 2; i++ {
		res := <-results
		if res.err != nil {
			errs = append(errs, fmt.Sprintf("%s telemetry did not flow with matching identity: %v", res.label, res.err))
		}
	}
	if len(errs) > 0 {
		return fmt.Errorf("%s", strings.Join(errs, "; "))
	}

	return nil
}

const (
	telemetryPollInterval = 15 * time.Second
	telemetryMaxAttempts  = 20
)

// pollUntilMatch polls search on a bounded budget until at least one returned event
// satisfies match, retrying the cloud (transient query errors, propagation delay) but
// never declaring success without a matching event.
func pollUntilMatch(
	ctx context.Context,
	_ *e2eshared.TelemetryClient,
	label string,
	search func(context.Context, string) ([]e2eshared.Event, error),
	query string,
	match func(e2eshared.Event) bool,
) error {
	var lastErr error
	for attempt := 1; attempt <= telemetryMaxAttempts; attempt++ {
		events, err := search(ctx, query)
		if err != nil {
			lastErr = err
		} else {
			for _, e := range events {
				if match(e) {
					return nil
				}
			}
			if len(events) > 0 {
				lastErr = fmt.Errorf("%d %s found for query %q but none carried the run identity", len(events), label, query)
			} else {
				lastErr = fmt.Errorf("no %s found yet for query %q", label, query)
			}
		}
		if attempt < telemetryMaxAttempts {
			select {
			case <-ctx.Done():
				return ctx.Err()
			case <-time.After(telemetryPollInterval):
			}
		}
	}

	return fmt.Errorf("[%s] timed out after %d attempts (%s): %w",
		label, telemetryMaxAttempts, time.Duration(telemetryMaxAttempts)*telemetryPollInterval, lastErr)
}
