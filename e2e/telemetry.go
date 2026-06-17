// Unless explicitly stated otherwise all files in this repository are licensed under the Apache-2.0 License.
// This product includes software developed at Datadog (https://www.datadoghq.com/) Copyright 2026 Datadog, Inc.

package e2e

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
)

const (
	pollInterval = 15 * time.Second
	maxAttempts  = 20
)

// telemetryConfig carries the Datadog API credentials and site for queries.
type telemetryConfig struct {
	apiKey string
	appKey string
	site   string
}

type searchResponse struct {
	Data []json.RawMessage `json:"data"`
}

// checkTelemetryFlowing polls spans and logs in parallel until each surfaces an
// event matching this run's identity, or the budget is exhausted. Identity is
// encoded in the query itself -- the unique service name, the env tag, and the
// run-id marker tag -- so a non-empty result asserts identity, not mere
// existence. (version is asserted in the config check; the tracer does not
// reliably stamp it on spans, which is upstream behaviour.)
func checkTelemetryFlowing(t *testing.T, cfg telemetryConfig, r run, env string) {
	t.Helper()

	query := fmt.Sprintf("service:%s env:%s %s:%s", r.serviceName, env, runIDTag, r.id)

	type result struct {
		label string
		err   error
	}
	results := make(chan result, 2)
	go func() {
		results <- result{"spans", pollUntilFound(t, "spans", func() (int, error) {
			return cfg.search(spansSearchPath, spansBody(query))
		})}
	}()
	go func() {
		results <- result{"logs", pollUntilFound(t, "logs", func() (int, error) {
			return cfg.search(logsSearchPath, logsBody(query))
		})}
	}()

	for i := 0; i < 2; i++ {
		res := <-results
		require.NoError(t, res.err, "%s telemetry did not flow with matching identity", res.label)
	}
}

// pollUntilFound polls query until it returns at least one event, bounding both
// the number of attempts and the wait between them.
func pollUntilFound(t *testing.T, label string, query func() (int, error)) error {
	t.Helper()
	for attempt := 1; attempt <= maxAttempts; attempt++ {
		t.Logf("[%s] attempt %d/%d", label, attempt, maxAttempts)
		n, err := query()
		if err != nil {
			t.Logf("[%s] query error: %v", label, err)
		} else if n > 0 {
			t.Logf("[%s] found %d event(s) matching run identity", label, n)

			return nil
		}
		if attempt < maxAttempts {
			time.Sleep(pollInterval)
		}
	}

	return fmt.Errorf("[%s] timed out after %d attempts (%s)", label, maxAttempts, time.Duration(maxAttempts)*pollInterval)
}

const (
	spansSearchPath = "/api/v2/spans/events/search"
	logsSearchPath  = "/api/v2/logs/events/search"
)

func timeWindow() (string, string) {
	now := time.Now().UTC()
	from := now.Add(-30 * time.Minute).Format(time.RFC3339)
	to := now.Add(5 * time.Minute).Format(time.RFC3339)

	return from, to
}

func spansBody(query string) []byte {
	from, to := timeWindow()
	body := map[string]any{
		"data": map[string]any{
			"type": "search_request",
			"attributes": map[string]any{
				"filter": map[string]any{"query": query, "from": from, "to": to},
				"page":   map[string]any{"limit": 25},
			},
		},
	}
	b, _ := json.Marshal(body) // body is constructed in-code; marshal can't fail

	return b
}

func logsBody(query string) []byte {
	from, to := timeWindow()
	body := map[string]any{
		"filter": map[string]any{"query": query, "from": from, "to": to},
		"page":   map[string]any{"limit": 25},
	}
	b, _ := json.Marshal(body) // body is constructed in-code; marshal can't fail

	return b
}

// search posts a v2 search request and returns the number of matched events.
func (cfg telemetryConfig) search(path string, body []byte) (int, error) {
	url := fmt.Sprintf("https://api.%s%s", cfg.site, path)
	req, err := http.NewRequest(http.MethodPost, url, bytes.NewReader(body))
	if err != nil {
		return 0, err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("DD-API-KEY", cfg.apiKey)
	req.Header.Set("DD-APPLICATION-KEY", cfg.appKey)

	client := &http.Client{Timeout: 30 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return 0, err
	}
	defer resp.Body.Close()

	raw, err := io.ReadAll(resp.Body)
	if err != nil {
		return 0, err
	}
	if resp.StatusCode != http.StatusOK {
		return 0, fmt.Errorf("search %s returned %d: %s", path, resp.StatusCode, string(raw))
	}

	var parsed searchResponse
	if err := json.Unmarshal(raw, &parsed); err != nil {
		return 0, fmt.Errorf("decoding search response: %w", err)
	}

	return len(parsed.Data), nil
}
