// Unless explicitly stated otherwise all files in this repository are licensed under the Apache-2.0 License.
// This product includes software developed at Datadog (https://www.datadoghq.com/) Copyright 2026 Datadog, Inc.

package e2e

import (
	"strings"
	"testing"
)

func TestVerifyInstrumented_SidecarOnly(t *testing.T) {
	t.Parallel()

	svc := cloudRunService{
		Labels: map[string]string{
			"service":                 "svc",
			"env":                     "e2e",
			"version":                 "1-0-0",
			"one_e2e_created":         "1710000000",
			"dd_sls_terraform_module": "2_2_0",
		},
		Template: template{
			Volumes: []volume{{
				Name:     sharedVolumeName,
				EmptyDir: &emptyDir{Medium: "MEMORY"},
			}},
			Containers: []container{
				{
					Name:  "app",
					Image: "app:latest",
					Env: []envVar{
						{Name: "DD_SERVICE", Value: "svc"},
						{Name: "DD_ENV", Value: "e2e"},
						{Name: "DD_VERSION", Value: "1-0-0"},
						{Name: "DD_TAGS", Value: "one_e2e_run_id:run1"},
						{Name: "DD_LOGS_INJECTION", Value: "true"},
						{Name: "DD_SERVERLESS_LOG_PATH", Value: "/shared-volume/logs/*.log"},
					},
					VolumeMounts: []volumeMount{{Name: sharedVolumeName, MountPath: "/shared-volume"}},
				},
				{
					Name:  sidecarName,
					Image: "sidecar@sha",
					Env: []envVar{
						{Name: "DD_API_KEY", Value: "secret"},
						{Name: "DD_SITE", Value: "datadoghq.com"},
						{Name: "DD_SERVICE", Value: "svc"},
						{Name: "DD_ENV", Value: "e2e"},
						{Name: "DD_VERSION", Value: "1-0-0"},
						{Name: "DD_TAGS", Value: "one_e2e_run_id:run1"},
						{Name: "DD_HEALTH_PORT", Value: "5555"},
						{Name: "DD_SERVERLESS_LOG_PATH", Value: "/shared-volume/logs/*.log"},
					},
					VolumeMounts: []volumeMount{{Name: sharedVolumeName, MountPath: "/shared-volume"}},
				},
			},
		},
	}

	err := verifyInstrumented(svc, Expectations{
		ServiceName:  "svc",
		Env:          "e2e",
		Version:      "1-0-0",
		RunID:        "run1",
		Site:         "datadoghq.com",
		SidecarImage: "sidecar@sha",
		CreatedTS:    "1710000000",
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
}

func TestVerifyInstrumented_SSIJS(t *testing.T) {
	t.Parallel()

	wantTags := "one_e2e_run_id:run1,_dd.injection.mode:serverless-single-lang"
	marker := "/datadog-lib/.dd-trace-js-copy-finished"
	svc := cloudRunService{
		Labels: map[string]string{
			"service":                 "svc",
			"env":                     "e2e",
			"version":                 "1-0-0",
			"one_e2e_created":         "1710000000",
			"dd_sls_terraform_module": "2_2_0",
		},
		Template: template{
			Volumes: []volume{
				{
					Name:     sharedVolumeName,
					EmptyDir: &emptyDir{Medium: "MEMORY"},
				},
				{
					Name:     tracerVolumeName,
					EmptyDir: &emptyDir{Medium: "MEMORY", SizeLimit: "500Mi"},
				},
			},
			Containers: []container{
				{
					Name:    "app",
					Image:   "app:latest",
					Command: []string{"sh", "-c"},
					Args: []string{
						"while [ ! -f '" + marker + "' ]; do sleep 0.1 2>/dev/null || :; done; exec \"$@\"",
						"dd-ssi-wait",
						"node",
						"index.js",
					},
					Env: []envVar{
						{Name: "DD_SERVICE", Value: "svc"},
						{Name: "DD_ENV", Value: "e2e"},
						{Name: "DD_VERSION", Value: "1-0-0"},
						{Name: "DD_TAGS", Value: wantTags},
						{Name: "DD_LOGS_INJECTION", Value: "true"},
						{Name: "DD_SERVERLESS_LOG_PATH", Value: "/shared-volume/logs/*.log"},
						{Name: "DD_TRACE_ENABLED", Value: "true"},
						{Name: "NODE_OPTIONS", Value: " --require=/datadog-lib/node_modules/dd-trace/init"},
					},
					VolumeMounts: []volumeMount{
						{Name: sharedVolumeName, MountPath: "/shared-volume"},
						{Name: tracerVolumeName, MountPath: tracerVolumePath},
					},
				},
				{
					Name:    "tracer-sidecar-js",
					Image:   "gcr.io/datadoghq/dd-lib-js-init:latest",
					Command: []string{"sh", "-c"},
					Args:    []string{"/datadog-init/copy-lib.sh /datadog-lib && while true; do :; done"},
					VolumeMounts: []volumeMount{
						{Name: tracerVolumeName, MountPath: tracerVolumePath},
					},
				},
				{
					Name:  sidecarName,
					Image: "sidecar@sha",
					Env: []envVar{
						{Name: "DD_API_KEY", Value: "secret"},
						{Name: "DD_SITE", Value: "datadoghq.com"},
						{Name: "DD_SERVICE", Value: "svc"},
						{Name: "DD_ENV", Value: "e2e"},
						{Name: "DD_VERSION", Value: "1-0-0"},
						{Name: "DD_TAGS", Value: wantTags},
						{Name: "DD_HEALTH_PORT", Value: "5555"},
						{Name: "DD_SERVERLESS_LOG_PATH", Value: "/shared-volume/logs/*.log"},
						{Name: "DD_TRACE_ENABLED", Value: "true"},
					},
					VolumeMounts: []volumeMount{{Name: sharedVolumeName, MountPath: "/shared-volume"}},
				},
			},
		},
	}

	err := verifyInstrumented(svc, Expectations{
		ServiceName:  "svc",
		Env:          "e2e",
		Version:      "1-0-0",
		RunID:        "run1",
		Site:         "datadoghq.com",
		SidecarImage: "sidecar@sha",
		CreatedTS:    "1710000000",
		SSI: &SSIExpectations{
			Language:      "js",
			TracerVersion: "latest",
			VolumeMedium:  "MEMORY",
		},
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
}

func TestVerifyInstrumented_SSIPython(t *testing.T) {
	t.Parallel()

	wantTags := "one_e2e_run_id:run1,_dd.injection.mode:serverless-single-lang"
	marker := "/datadog-lib/.dd-trace-py-copy-finished"
	svc := cloudRunService{
		Labels: map[string]string{
			"service":                 "svc",
			"env":                     "e2e",
			"version":                 "1-0-0",
			"one_e2e_created":         "1710000000",
			"dd_sls_terraform_module": "2_2_0",
		},
		Template: template{
			Volumes: []volume{
				{
					Name:     sharedVolumeName,
					EmptyDir: &emptyDir{Medium: "MEMORY"},
				},
				{
					Name:     tracerVolumeName,
					EmptyDir: &emptyDir{Medium: "MEMORY", SizeLimit: "500Mi"},
				},
			},
			Containers: []container{
				{
					Name:    "app",
					Image:   "app:latest",
					Command: []string{"sh", "-c"},
					Args: []string{
						"while [ ! -f '" + marker + "' ]; do sleep 0.1 2>/dev/null || :; done; exec \"$@\"",
						"dd-ssi-wait",
						"python",
						"app.py",
					},
					Env: []envVar{
						{Name: "DD_SERVICE", Value: "svc"},
						{Name: "DD_ENV", Value: "e2e"},
						{Name: "DD_VERSION", Value: "1-0-0"},
						{Name: "DD_TAGS", Value: wantTags},
						{Name: "DD_LOGS_INJECTION", Value: "true"},
						{Name: "DD_SERVERLESS_LOG_PATH", Value: "/shared-volume/logs/*.log"},
						{Name: "DD_TRACE_ENABLED", Value: "true"},
						{Name: "PYTHONPATH", Value: "/datadog-lib/"},
						{Name: "DD_INJECT_EXPERIMENTAL_OVERRIDE_USER_DDTRACE", Value: "true"},
					},
					VolumeMounts: []volumeMount{
						{Name: sharedVolumeName, MountPath: "/shared-volume"},
						{Name: tracerVolumeName, MountPath: tracerVolumePath},
					},
				},
				{
					Name:    "tracer-sidecar-python",
					Image:   "gcr.io/datadoghq/dd-lib-python-init:latest",
					Command: []string{"sh", "-c"},
					Args:    []string{"/datadog-init/copy-lib.sh /datadog-lib && while true; do :; done"},
					VolumeMounts: []volumeMount{
						{Name: tracerVolumeName, MountPath: tracerVolumePath},
					},
				},
				{
					Name:  sidecarName,
					Image: "sidecar@sha",
					Env: []envVar{
						{Name: "DD_API_KEY", Value: "secret"},
						{Name: "DD_SITE", Value: "datadoghq.com"},
						{Name: "DD_SERVICE", Value: "svc"},
						{Name: "DD_ENV", Value: "e2e"},
						{Name: "DD_VERSION", Value: "1-0-0"},
						{Name: "DD_TAGS", Value: wantTags},
						{Name: "DD_HEALTH_PORT", Value: "5555"},
						{Name: "DD_SERVERLESS_LOG_PATH", Value: "/shared-volume/logs/*.log"},
						{Name: "DD_TRACE_ENABLED", Value: "true"},
					},
					VolumeMounts: []volumeMount{{Name: sharedVolumeName, MountPath: "/shared-volume"}},
				},
			},
		},
	}

	err := verifyInstrumented(svc, Expectations{
		ServiceName:  "svc",
		Env:          "e2e",
		Version:      "1-0-0",
		RunID:        "run1",
		Site:         "datadoghq.com",
		SidecarImage: "sidecar@sha",
		CreatedTS:    "1710000000",
		SSI: &SSIExpectations{
			Language:      "python",
			TracerVersion: "latest",
			VolumeMedium:  "MEMORY",
		},
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
}

func TestVerifyInstrumented_SSIMissingTracerSidecar(t *testing.T) {
	t.Parallel()

	svc := cloudRunService{
		Labels: map[string]string{
			"service":                 "svc",
			"env":                     "e2e",
			"version":                 "1-0-0",
			"one_e2e_created":         "1710000000",
			"dd_sls_terraform_module": "2_2_0",
		},
		Template: template{
			Volumes: []volume{
				{Name: sharedVolumeName, EmptyDir: &emptyDir{Medium: "MEMORY"}},
				{Name: tracerVolumeName, EmptyDir: &emptyDir{Medium: "MEMORY", SizeLimit: "500Mi"}},
			},
			Containers: []container{
				{
					Name:    "app",
					Image:   "app:latest",
					Command: []string{"sh", "-c"},
					Args: []string{
						"while [ ! -f '/datadog-lib/.dd-trace-js-copy-finished' ]; do :; done; exec \"$@\"",
						"dd-ssi-wait",
						"node",
					},
					Env: []envVar{
						{Name: "DD_SERVICE", Value: "svc"},
						{Name: "DD_ENV", Value: "e2e"},
						{Name: "DD_VERSION", Value: "1-0-0"},
						{Name: "DD_TAGS", Value: "one_e2e_run_id:run1,_dd.injection.mode:serverless-single-lang"},
						{Name: "DD_LOGS_INJECTION", Value: "true"},
						{Name: "DD_SERVERLESS_LOG_PATH", Value: "/shared-volume/logs/*.log"},
						{Name: "DD_TRACE_ENABLED", Value: "true"},
						{Name: "NODE_OPTIONS", Value: " --require=/datadog-lib/node_modules/dd-trace/init"},
					},
					VolumeMounts: []volumeMount{
						{Name: sharedVolumeName, MountPath: "/shared-volume"},
						{Name: tracerVolumeName, MountPath: tracerVolumePath},
					},
				},
				{
					Name:  sidecarName,
					Image: "sidecar@sha",
					Env: []envVar{
						{Name: "DD_API_KEY", Value: "secret"},
						{Name: "DD_SITE", Value: "datadoghq.com"},
						{Name: "DD_SERVICE", Value: "svc"},
						{Name: "DD_ENV", Value: "e2e"},
						{Name: "DD_VERSION", Value: "1-0-0"},
						{Name: "DD_TAGS", Value: "one_e2e_run_id:run1,_dd.injection.mode:serverless-single-lang"},
						{Name: "DD_HEALTH_PORT", Value: "5555"},
						{Name: "DD_SERVERLESS_LOG_PATH", Value: "/shared-volume/logs/*.log"},
						{Name: "DD_TRACE_ENABLED", Value: "true"},
					},
					VolumeMounts: []volumeMount{{Name: sharedVolumeName, MountPath: "/shared-volume"}},
				},
			},
		},
	}

	err := verifyInstrumented(svc, Expectations{
		ServiceName:  "svc",
		Env:          "e2e",
		Version:      "1-0-0",
		RunID:        "run1",
		Site:         "datadoghq.com",
		SidecarImage: "sidecar@sha",
		CreatedTS:    "1710000000",
		SSI: &SSIExpectations{
			Language:      "js",
			TracerVersion: "latest",
			VolumeMedium:  "MEMORY",
		},
	})
	if err == nil {
		t.Fatal("expected error for missing tracer sidecar")
	}
	if !strings.Contains(err.Error(), "tracer sidecar") {
		t.Fatalf("error should mention tracer sidecar, got: %v", err)
	}
}

func TestExpectedDDTags(t *testing.T) {
	t.Parallel()

	if got := expectedDDTags("abc", false); got != "one_e2e_run_id:abc" {
		t.Fatalf("got %q", got)
	}
	if got := expectedDDTags("abc", true); got != "one_e2e_run_id:abc,_dd.injection.mode:serverless-single-lang" {
		t.Fatalf("got %q", got)
	}
}
