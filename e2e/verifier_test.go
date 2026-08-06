// Unless explicitly stated otherwise all files in this repository are licensed under the Apache-2.0 License.
// This product includes software developed at Datadog (https://www.datadoghq.com/) Copyright 2026 Datadog, Inc.

package e2e

import (
	"fmt"
	"strings"
	"testing"
)

// tracerSidecarContainer mirrors the copy container the module injects: it copies the
// tracer, verifies the marker, then execs the listener that holds the readiness port open.
func tracerSidecarContainer(language string) container {
	return container{
		Name:         tracerSidecarName(language),
		Image:        fmt.Sprintf("gcr.io/datadoghq/dd-lib-%s-init:latest", language),
		Command:      []string{"sh", "-c"},
		Args:         []string{tracerSidecarArgs(language)},
		VolumeMounts: []volumeMount{{Name: tracerVolumeName, MountPath: tracerVolumePath}},
		StartupProbe: &probe{TCPSocket: &tcpSocketAction{Port: defaultReadyPort}},
	}
}

// tracerSidecarArgs mirrors the copy-verify-listen script the module builds.
func tracerSidecarArgs(language string) string {
	return fmt.Sprintf(
		"/datadog-init/copy-lib.sh %s && [ -f '%s' ] && exec %s %d; echo 'datadog: tracer copy did not finish, not opening %d' >&2; exit 1",
		tracerVolumePath, copyFinishedMarker(language), probeServerPath,
		defaultReadyPort, defaultReadyPort,
	)
}

func ssiExpectations(language string) *SSIExpectations {
	return &SSIExpectations{
		Language:      language,
		TracerVersion: "latest",
		VolumeMedium:  "MEMORY",
		ReadyPort:     defaultReadyPort,
	}
}

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
					Name:      "app",
					Image:     "app:latest",
					DependsOn: []string{tracerSidecarName("js")},
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
				tracerSidecarContainer("js"),
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
		SSI:          ssiExpectations("js"),
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
}

func TestVerifyInstrumented_SSIPython(t *testing.T) {
	t.Parallel()

	wantTags := "one_e2e_run_id:run1,_dd.injection.mode:serverless-single-lang"
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
					Name:      "app",
					Image:     "app:latest",
					DependsOn: []string{tracerSidecarName("python")},
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
				tracerSidecarContainer("python"),
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
		SSI:          ssiExpectations("python"),
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
}

// ssiJSService builds a valid SSI-instrumented service that the negative tests below
// break in exactly one way.
func ssiJSService() cloudRunService {
	wantTags := "one_e2e_run_id:run1,_dd.injection.mode:serverless-single-lang"

	return cloudRunService{
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
					Name:      "app",
					Image:     "app:latest",
					DependsOn: []string{tracerSidecarName("js")},
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
				tracerSidecarContainer("js"),
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
}

func ssiJSTestExpectations() Expectations {
	return Expectations{
		ServiceName:  "svc",
		Env:          "e2e",
		Version:      "1-0-0",
		RunID:        "run1",
		Site:         "datadoghq.com",
		SidecarImage: "sidecar@sha",
		CreatedTS:    "1710000000",
		SSI:          ssiExpectations("js"),
	}
}

func TestVerifyInstrumented_SSIMissingTracerSidecar(t *testing.T) {
	t.Parallel()

	svc := ssiJSService()
	svc.Template.Containers = append(
		svc.Template.Containers[:1],
		svc.Template.Containers[2:]...,
	)

	err := verifyInstrumented(svc, ssiJSTestExpectations())
	if err == nil {
		t.Fatal("expected error for missing tracer sidecar")
	}
	if !strings.Contains(err.Error(), "tracer sidecar") {
		t.Fatalf("error should mention tracer sidecar, got: %v", err)
	}
}

// The app container must be sequenced by container start order rather than a rewritten
// entrypoint, otherwise it can boot before the tracer is copied.
func TestVerifyInstrumented_SSIAppMissingTracerDependency(t *testing.T) {
	t.Parallel()

	svc := ssiJSService()
	svc.Template.Containers[0].DependsOn = nil

	err := verifyInstrumented(svc, ssiJSTestExpectations())
	if err == nil {
		t.Fatal("expected error for app container without a tracer sidecar dependency")
	}
	if !strings.Contains(err.Error(), "dependsOn") {
		t.Fatalf("error should mention dependsOn, got: %v", err)
	}
}

func TestVerifyInstrumented_SSIAppStartupRewritten(t *testing.T) {
	t.Parallel()

	svc := ssiJSService()
	svc.Template.Containers[0].Command = []string{"sh", "-c"}
	svc.Template.Containers[0].Args = []string{
		"while [ ! -f '/datadog-lib/.dd-trace-js-copy-finished' ]; do :; done; exec \"$@\"",
		"node",
		"index.js",
	}

	err := verifyInstrumented(svc, ssiJSTestExpectations())
	if err == nil {
		t.Fatal("expected error for app container with a rewritten entrypoint")
	}
	if !strings.Contains(err.Error(), "image entrypoint") {
		t.Fatalf("error should mention the image entrypoint, got: %v", err)
	}
}

// A tracer sidecar that only copies leaves nothing for the startup probe to reach, so the
// app would never be released.
func TestVerifyInstrumented_SSIListenerNotStarted(t *testing.T) {
	t.Parallel()

	svc := ssiJSService()
	svc.Template.Containers[1].Args = []string{
		fmt.Sprintf("/datadog-init/copy-lib.sh %s && while true; do :; done", tracerVolumePath),
	}

	err := verifyInstrumented(svc, ssiJSTestExpectations())
	if err == nil {
		t.Fatal("expected error for a tracer sidecar that never starts the listener")
	}
	if !strings.Contains(err.Error(), probeServerPath) {
		t.Fatalf("error should mention %s, got: %v", probeServerPath, err)
	}
}

// copy-lib.sh exits 0 after wiping a partial copy, so opening the port without testing the
// marker would release the app onto an empty volume.
func TestVerifyInstrumented_SSIListenerSkipsMarkerCheck(t *testing.T) {
	t.Parallel()

	svc := ssiJSService()
	svc.Template.Containers[1].Args = []string{
		fmt.Sprintf(
			"/datadog-init/copy-lib.sh %s && exec %s %d",
			tracerVolumePath, probeServerPath, defaultReadyPort,
		),
	}

	err := verifyInstrumented(svc, ssiJSTestExpectations())
	if err == nil {
		t.Fatal("expected error for a listener started without verifying the copy marker")
	}
	if !strings.Contains(err.Error(), "copy marker") {
		t.Fatalf("error should mention the copy marker, got: %v", err)
	}
}

// Without the probe, Cloud Run releases dependents immediately and the copy is not waited on.
func TestVerifyInstrumented_SSITracerSidecarWithoutStartupProbe(t *testing.T) {
	t.Parallel()

	svc := ssiJSService()
	svc.Template.Containers[1].StartupProbe = nil

	err := verifyInstrumented(svc, ssiJSTestExpectations())
	if err == nil {
		t.Fatal("expected error for a tracer sidecar without a startup probe")
	}
	if !strings.Contains(err.Error(), "startup probe") {
		t.Fatalf("error should mention the startup probe, got: %v", err)
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
