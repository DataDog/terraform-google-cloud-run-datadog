// Unless explicitly stated otherwise all files in this repository are licensed under the Apache-2.0 License.
// This product includes software developed at Datadog (https://www.datadoghq.com/) Copyright 2026 Datadog, Inc.

package e2e

import (
	"context"
	"fmt"
	"sort"
	"strings"
	"testing"
	"time"

	e2eshared "github.com/DataDog/terraform-google-cloud-run-datadog/e2e/shared"
)

// checkTelemetryFlowing polls spans and logs in parallel until both surface an event
// matching this run's identity (service + env + run-id)
func checkTelemetryFlowing(ctx context.Context, t *testing.T, client *e2eshared.TelemetryClient, serviceName, runID, env, uri string) error {
	tctx, stopTraffic := context.WithCancel(ctx)
	defer stopTraffic()
	go e2eshared.GenerateTraffic(tctx, uri, 5*time.Second)

	// service + env + run-id marker, no version (see doc comment).
	query := fmt.Sprintf("service:%s env:%s %s:%s", serviceName, env, e2eshared.DefaultRunIDTagKey, runID)
	want := matchWant{
		Service: serviceName,
		Env:     env,
		RunID:   runID,
	}
	t.Logf("telemetry query=%q", query)

	type result struct {
		label string
		err   error
	}
	results := make(chan result, 2)
	go func() {
		results <- result{"spans", pollUntilMatch(ctx, t, "spans", client.SearchSpans, query, want)}
	}()
	go func() {
		results <- result{"logs", pollUntilMatch(ctx, t, "logs", client.SearchLogs, query, want)}
	}()

	var errs []string
	for range 2 {
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
	// Cap how many events we dump per failed attempt to keep CI logs readable.
	telemetryDebugEventLimit = 3
)

type matchWant struct {
	Service string
	Env     string
	RunID   string
}

// matchGaps lists which required fields are missing from an event.
func matchGaps(e e2eshared.Event, want matchWant) []string {
	var gaps []string
	if !e.Has("service", want.Service) {
		gaps = append(gaps, fmt.Sprintf("service!=%q (got %q)", want.Service, attrOrTag(e, "service")))
	}
	if !e.Has("env", want.Env) {
		gaps = append(gaps, fmt.Sprintf("env!=%q (got %q)", want.Env, attrOrTag(e, "env")))
	}
	if !e.Has(e2eshared.DefaultRunIDTagKey, want.RunID) {
		gaps = append(gaps, fmt.Sprintf("%s!=%q (got %q)", e2eshared.DefaultRunIDTagKey, want.RunID, attrOrTag(e, e2eshared.DefaultRunIDTagKey)))
	}

	return gaps
}

func attrOrTag(e e2eshared.Event, key string) string {
	if v, ok := e.Attrs[key]; ok && v != "" {
		return v
	}
	prefix := key + ":"
	for _, tag := range e.Tags {
		if strings.HasPrefix(tag, prefix) {
			return strings.TrimPrefix(tag, prefix)
		}
	}

	return "<missing>"
}

func formatEventDebug(e e2eshared.Event) string {
	keys := make([]string, 0, len(e.Attrs))
	for k := range e.Attrs {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	attrs := make([]string, 0, len(keys))
	for _, k := range keys {
		attrs = append(attrs, fmt.Sprintf("%s=%q", k, e.Attrs[k]))
	}
	tags := append([]string(nil), e.Tags...)
	sort.Strings(tags)
	if len(tags) > 20 {
		tags = append(tags[:20], fmt.Sprintf("...(+%d more)", len(e.Tags)-20))
	}

	return fmt.Sprintf("attrs{%s} tags[%s]", strings.Join(attrs, " "), strings.Join(tags, ", "))
}

// pollUntilMatch polls search on a bounded budget until at least one returned event
// satisfies match, retrying the cloud (transient query errors, propagation delay) but
// never declaring success without a matching event.
func pollUntilMatch(
	ctx context.Context,
	t *testing.T,
	label string,
	search func(context.Context, string) ([]e2eshared.Event, error),
	query string,
	want matchWant,
) error {
	var lastErr error
	for attempt := 1; attempt <= telemetryMaxAttempts; attempt++ {
		t.Logf("checking %s telemetry (attempt %d/%d)", label, attempt, telemetryMaxAttempts)
		events, err := search(ctx, query)
		if err != nil {
			t.Logf("%s search error: %v", label, err)
			lastErr = err
		} else if len(events) == 0 {
			t.Logf("%s: 0 events for query %q", label, query)
			lastErr = fmt.Errorf("no %s found yet for query %q", label, query)
		} else {
			var matched bool
			for i, e := range events {
				gaps := matchGaps(e, want)
				if len(gaps) == 0 {
					t.Logf("found matching %s telemetry", label)
					matched = true
					break
				}
				if i < telemetryDebugEventLimit {
					t.Logf("%s event[%d] gaps=%v %s", label, i, gaps, formatEventDebug(e))
				}
			}
			if matched {
				return nil
			}
			if len(events) > telemetryDebugEventLimit {
				t.Logf("%s: ... truncated debug for %d additional events", label, len(events)-telemetryDebugEventLimit)
			}
			// Summarize the most common gap across the page for the final error.
			gapCounts := map[string]int{}
			for _, e := range events {
				for _, g := range matchGaps(e, want) {
					// Collapse to the field name before "!=" for a short summary.
					field := strings.SplitN(g, "!=", 2)[0]
					gapCounts[field]++
				}
			}
			lastErr = fmt.Errorf("%d %s found for query %q but none matched (gap counts: %v)",
				len(events), label, query, gapCounts)
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
