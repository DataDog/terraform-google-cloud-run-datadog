// Unless explicitly stated otherwise all files in this repository are licensed under the Apache-2.0 License.
// This product includes software developed at Datadog (https://www.datadoghq.com/) Copyright 2026 Datadog, Inc.

package e2e

import (
	"os/exec"
	"strings"
	"time"
)

// retryablePatterns are transient cloud/control-plane errors that are safe to
// retry. We retry the cloud, never a real assertion failure -- so only these
// substrings trigger a retry, mirroring the reference impl's allow-list.
var retryablePatterns = []string{
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
}

// commandResult is the outcome of a single command invocation.
type commandResult struct {
	stdout   string
	stderr   string
	exitCode int
	err      error
}

func isRetryable(r commandResult) bool {
	out := r.stdout + " " + r.stderr
	for _, p := range retryablePatterns {
		if strings.Contains(out, p) {
			return true
		}
	}

	return false
}

func runOnce(name string, args ...string) commandResult {
	cmd := exec.Command(name, args...)
	var stdout, stderr strings.Builder
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr
	err := cmd.Run()

	res := commandResult{stdout: stdout.String(), stderr: stderr.String(), err: err}
	if err != nil {
		if exitErr, ok := err.(*exec.ExitError); ok {
			res.exitCode = exitErr.ExitCode()
		} else {
			res.exitCode = 1
		}
	}

	return res
}

// runWithRetries runs a command up to maxAttempts times, retrying only on
// transient cloud errors with a fixed backoff. The final result is returned
// regardless of exit code so callers can assert on it.
func runWithRetries(maxAttempts int, delay time.Duration, name string, args ...string) commandResult {
	var res commandResult
	for attempt := 1; attempt <= maxAttempts; attempt++ {
		res = runOnce(name, args...)
		if res.exitCode == 0 {
			return res
		}
		if attempt < maxAttempts && isRetryable(res) {
			time.Sleep(delay)
			continue
		}

		return res
	}

	return res
}
