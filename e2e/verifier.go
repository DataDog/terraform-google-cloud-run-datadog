// Unless explicitly stated otherwise all files in this repository are licensed under the Apache-2.0 License.
// This product includes software developed at Datadog (https://www.datadoghq.com/) Copyright 2026 Datadog, Inc.

package e2e

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"

	run "cloud.google.com/go/run/apiv2"
	runpb "cloud.google.com/go/run/apiv2/runpb"
	e2eshared "github.com/DataDog/terraform-google-cloud-run-datadog/e2e/shared"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
	"google.golang.org/protobuf/encoding/protojson"
)

// Names the module assigns to the components it injects.
const (
	sidecarName      = "datadog-sidecar"
	sharedVolumeName = "shared-volume"
	tracerVolumeName = "datadog-tracer"
	tracerVolumePath = "/datadog-lib"
	injectionModeTag = "_dd.injection.mode:serverless-single-lang"
	defaultReadyPort = 5100
	probeServerPath  = "/datadog-init/probe-server"

	// freshnessLabel is the GCP label key carrying the creation timestamp. Label keys
	// cannot contain ':', so the spec's one_e2e_created:<ts> tag is expressed as the
	// key=value label one_e2e_created=<ts>. It mirrors the shared freshness tag key.
	freshnessLabel = e2eshared.DefaultFreshnessTagKey
)

// These types mirror the Cloud Run v2 API response after protojson conversion.
type envVar struct {
	Name  string `json:"name"`
	Value string `json:"value"`
}

type volumeMount struct {
	Name      string `json:"name"`
	MountPath string `json:"mountPath"`
}

type tcpSocketAction struct {
	Port int `json:"port"`
}

type probe struct {
	TCPSocket *tcpSocketAction `json:"tcpSocket"`
}

type container struct {
	Name         string        `json:"name"`
	Image        string        `json:"image"`
	Command      []string      `json:"command"`
	Args         []string      `json:"args"`
	Env          []envVar      `json:"env"`
	VolumeMounts []volumeMount `json:"volumeMounts"`
	DependsOn    []string      `json:"dependsOn"`
	StartupProbe *probe        `json:"startupProbe"`
}

type emptyDir struct {
	Medium    string `json:"medium"`
	SizeLimit string `json:"sizeLimit"`
}

type volume struct {
	Name     string    `json:"name"`
	EmptyDir *emptyDir `json:"emptyDir"`
}

type template struct {
	Containers []container `json:"containers"`
	Volumes    []volume    `json:"volumes"`
}

type cloudRunService struct {
	Labels   map[string]string `json:"labels"`
	Template template          `json:"template"`
}

// SSIExpectations pins Single-Language SSI wiring the module must produce.
type SSIExpectations struct {
	Language        string
	TracerVersion   string
	VolumeMedium    string
	ReadyPort       int
	TracerInitImage string
}

// tracerInitImage is the image the tracer sidecar must run, defaulting to the published
// init image for the language when no override is expected.
func (s *SSIExpectations) tracerInitImage() string {
	if s.TracerInitImage != "" {
		return s.TracerInitImage
	}

	return fmt.Sprintf("gcr.io/datadoghq/dd-lib-%s-init:%s", s.Language, s.TracerVersion)
}

// Expectations pins what an instrumented Cloud Run service must look like, so a mismatch
// blames the module wiring rather than upstream drift.
type Expectations struct {
	ServiceName  string
	Env          string
	Version      string
	RunID        string
	Site         string
	SidecarImage string
	CreatedTS    string
	// SSI is nil when datadog_apm_instrumentation is unset.
	SSI *SSIExpectations
}

func (s cloudRunService) getTemplate() template {
	return s.Template
}

func (s cloudRunService) getLabels() map[string]string {
	return s.Labels
}

// envMap flattens a container's env vars into a map for the shared verification helpers.
func (c container) envMap() map[string]string {
	m := make(map[string]string, len(c.Env))
	for _, e := range c.Env {
		m[e.Name] = e.Value
	}

	return m
}

func (c container) hasMount(volumeName, mountPath string) bool {
	for _, m := range c.VolumeMounts {
		if m.Name == volumeName && m.MountPath == mountPath {
			return true
		}
	}

	return false
}

// describeService fetches the service through the Cloud Run API using Application
// Default Credentials, then converts the response into the verifier's compact shape.
func describeService(ctx context.Context, client *run.ServicesClient, serviceName, project, region string) (cloudRunService, error) {
	name := fmt.Sprintf("projects/%s/locations/%s/services/%s", project, region, serviceName)
	service, err := client.GetService(ctx, &runpb.GetServiceRequest{Name: name})
	if err != nil {
		return cloudRunService{}, fmt.Errorf("get Cloud Run service %q: %w", name, err)
	}

	raw, err := protojson.Marshal(service)
	if err != nil {
		return cloudRunService{}, fmt.Errorf("marshal Cloud Run service %q: %w", name, err)
	}

	var parsed cloudRunService
	if err := json.Unmarshal(raw, &parsed); err != nil {
		return cloudRunService{}, fmt.Errorf("parse Cloud Run service %q: %w", name, err)
	}

	return parsed, nil
}

func expectedDDTags(runID string, ssi bool) string {
	tags := []string{e2eshared.DefaultRunIDTagKey + ":" + runID}
	if ssi {
		tags = append(tags, injectionModeTag)
	}

	return strings.Join(tags, ",")
}

func tracerSidecarName(language string) string {
	return "tracer-sidecar-" + language
}

func tracerRepoName(language string) string {
	return map[string]string{
		"java":   "dd-trace-java",
		"js":     "dd-trace-js",
		"python": "dd-trace-py",
		"dotnet": "dd-trace-dotnet",
		"ruby":   "dd-trace-rb",
		"php":    "dd-trace-php",
	}[language]
}

func ssiLanguageEnv(language string) map[string]string {
	switch language {
	case "js":
		return map[string]string{
			"NODE_OPTIONS": " --require=" + tracerVolumePath + "/node_modules/dd-trace/init",
		}
	case "python":
		return map[string]string{
			"PYTHONPATH": tracerVolumePath + "/",
			"DD_INJECT_EXPERIMENTAL_OVERRIDE_USER_DDTRACE": "true",
		}
	case "java":
		return map[string]string{
			"JAVA_TOOL_OPTIONS": " -javaagent:" + tracerVolumePath + "/dd-java-agent.jar -XX:OnError=" + tracerVolumePath + "/java/continuousprofiler/tmp/dd_crash_uploader.sh -XX:ErrorFile=" + tracerVolumePath + "/java/continuousprofiler/tmp/hs_err_pid_%p.log",
		}
	case "dotnet":
		return map[string]string{
			"CORECLR_ENABLE_PROFILING": "1",
			"CORECLR_PROFILER":         "{846F5F1C-F9AE-4B07-969E-05C26BC060D8}",
			"CORECLR_PROFILER_PATH":    tracerVolumePath + "/Datadog.Trace.ClrProfiler.Native.so",
			"DD_DOTNET_TRACER_HOME":    tracerVolumePath,
			"DD_TRACE_LOG_DIRECTORY":   tracerVolumePath + "/logs",
			"LD_PRELOAD":               tracerVolumePath + "/continuousprofiler/Datadog.Linux.ApiWrapper.x64.so",
		}
	case "ruby":
		return map[string]string{
			"RUBYOPT": " -r" + tracerVolumePath + "/auto_inject",
		}
	case "php":
		return map[string]string{
			"PHP_INI_SCAN_DIR":       tracerVolumePath + "/linux-gnu/loader",
			"DD_LOADER_PACKAGE_PATH": tracerVolumePath,
		}
	default:
		return nil
	}
}

// verifyInstrumented asserts the module produced a correctly instrumented service: the
// sidecar + shared volume + mounts are present, the wiring env vars are set, and the
// identifying labels hold the expected *values* (identity, not mere existence).
func verifyInstrumented(svc cloudRunService, exp Expectations) error {
	var v e2eshared.Violations

	tmpl := svc.getTemplate()
	containers := tmpl.Containers
	if len(containers) == 0 {
		v.Addf("service has no containers")

		return v.Err("instrumented contract violated")
	}

	ssiEnabled := exp.SSI != nil
	wantTags := expectedDDTags(exp.RunID, ssiEnabled)

	// Sidecar: present and running the pinned serverless-init image.
	var sidecar *container
	for i := range containers {
		if containers[i].Name == sidecarName {
			sidecar = &containers[i]
		}
	}
	if sidecar == nil {
		v.Addf("datadog-sidecar container missing")
	} else {
		if sidecar.Image != exp.SidecarImage {
			v.Addf("sidecar image = %q, want pinned image %q", sidecar.Image, exp.SidecarImage)
		}

		// The module-owned volume must retain its expected in-memory configuration.
		sharedVolume, ok := findVolume(tmpl.Volumes, sharedVolumeName)
		if !ok {
			v.Addf("shared volume %q missing", sharedVolumeName)
		} else if sharedVolume.EmptyDir == nil {
			v.Addf("shared volume %q is not an emptyDir volume", sharedVolumeName)
		} else {
			if sharedVolume.EmptyDir.Medium != "MEMORY" {
				v.Addf("shared volume medium = %q, want MEMORY", sharedVolume.EmptyDir.Medium)
			}
			if sharedVolume.EmptyDir.SizeLimit != "" {
				v.Addf("shared volume size limit = %q, want unset", sharedVolume.EmptyDir.SizeLimit)
			}
		}
		if !sidecar.hasMount(sharedVolumeName, "/shared-volume") {
			v.Addf("sidecar does not mount shared volume %q at /shared-volume", sharedVolumeName)
		}

		// API-key wiring + identity env vars live on the sidecar (the agent).
		sidecarEnv := sidecar.envMap()
		e2eshared.RequirePresent(&v, "sidecar env var", sidecarEnv, "DD_API_KEY")
		e2eshared.RequireValues(&v, "sidecar env var", sidecarEnv, map[string]string{
			"DD_SITE":                exp.Site,
			"DD_SERVICE":             exp.ServiceName,
			"DD_ENV":                 exp.Env,
			"DD_VERSION":             exp.Version,
			"DD_TAGS":                wantTags,
			"DD_HEALTH_PORT":         "5555",
			"DD_SERVERLESS_LOG_PATH": "/shared-volume/logs/*.log",
		})
		if ssiEnabled {
			e2eshared.RequireValues(&v, "sidecar env var", sidecarEnv, map[string]string{
				"DD_TRACE_ENABLED": "true",
			})
		}
	}

	// App containers: log-injection + identity env vars, plus the log volume.
	appContainers := 0
	for i := range containers {
		c := &containers[i]
		if c.Name == sidecarName || strings.HasPrefix(c.Name, "tracer-sidecar-") {
			continue
		}
		appContainers++
		appEnv := c.envMap()
		e2eshared.RequireValues(&v, fmt.Sprintf("app container %q env var", c.Name), appEnv, map[string]string{
			"DD_SERVICE":             exp.ServiceName,
			"DD_ENV":                 exp.Env,
			"DD_VERSION":             exp.Version,
			"DD_LOGS_INJECTION":      "true",
			"DD_SERVERLESS_LOG_PATH": "/shared-volume/logs/*.log",
			"DD_TAGS":                wantTags,
		})
		if !c.hasMount(sharedVolumeName, "/shared-volume") {
			v.Addf("app container %q does not mount shared volume %q at /shared-volume", c.Name, sharedVolumeName)
		}
		if ssiEnabled {
			verifyAppSSI(&v, c, exp.SSI)
		} else if c.hasMount(tracerVolumeName, tracerVolumePath) {
			v.Addf("app container %q unexpectedly mounts tracer volume %q", c.Name, tracerVolumeName)
		}
	}
	if appContainers == 0 {
		v.Addf("service has no app containers")
	}

	if ssiEnabled {
		verifyTracerSidecar(&v, tmpl, exp.SSI)
	} else {
		for _, c := range containers {
			if strings.HasPrefix(c.Name, "tracer-sidecar-") {
				v.Addf("unexpected tracer container %q when SSI is disabled", c.Name)
			}
		}
		if _, ok := findVolume(tmpl.Volumes, tracerVolumeName); ok {
			v.Addf("unexpected tracer volume %q when SSI is disabled", tracerVolumeName)
		}
	}

	// Identifying labels carry the expected values. version is mirrored into a label
	// (label-safe form) even though it is not reliably stamped on spans.
	labels := svc.getLabels()
	e2eshared.RequireValues(&v, "label", labels, map[string]string{
		"service":      exp.ServiceName,
		"env":          exp.Env,
		"version":      exp.Version,
		freshnessLabel: exp.CreatedTS,
	})
	if labels["dd_sls_terraform_module"] == "" {
		v.Addf("missing dd_sls_terraform_module module marker label")
	}

	return v.Err("instrumented contract violated")
}

func verifyAppSSI(v *e2eshared.Violations, app *container, ssi *SSIExpectations) {
	if !app.hasMount(tracerVolumeName, tracerVolumePath) {
		v.Addf("app container %q does not mount tracer volume at %s", app.Name, tracerVolumePath)
	}

	appEnv := app.envMap()
	e2eshared.RequireValues(v, fmt.Sprintf("app container %q env var", app.Name), appEnv, map[string]string{
		"DD_TRACE_ENABLED": "true",
	})
	e2eshared.RequireValues(v, fmt.Sprintf("app container %q SSI env var", app.Name), appEnv, ssiLanguageEnv(ssi.Language))

	// Startup is sequenced by container start order, so the workload entrypoint must be
	// left alone: no marker wait script may appear in command or args.
	wantDep := tracerSidecarName(ssi.Language)
	if !containsString(app.DependsOn, wantDep) {
		v.Addf("app container %q dependsOn = %#v, want it to include %q", app.Name, app.DependsOn, wantDep)
	}
	marker := copyFinishedMarker(ssi.Language)
	for _, arg := range append(append([]string{}, app.Command...), app.Args...) {
		if strings.Contains(arg, marker) {
			v.Addf("app container %q startup was rewritten with a marker wait (%q); it should keep its image entrypoint", app.Name, arg)

			break
		}
	}
}

// verifyTracerReadiness checks the sidecar copies, gates on the marker, and only then execs
// the listener that the app containers' startup probe waits on.
func verifyTracerReadiness(v *e2eshared.Violations, tracer *container, ssi *SSIExpectations) {
	invocation := containerInvocation(tracer)

	wantListener := fmt.Sprintf("exec %s %d", probeServerPath, ssi.ReadyPort)
	if !strings.Contains(invocation, wantListener) {
		v.Addf("tracer sidecar does not exec the probe server (%q): %q", wantListener, invocation)
	}
	if marker := copyFinishedMarker(ssi.Language); !strings.Contains(invocation, marker) {
		v.Addf("tracer sidecar opens the readiness port without checking the copy marker %q: %q", marker, invocation)
	}

	// Without this probe Cloud Run starts dependents immediately, which would let the
	// app boot before the tracer is in place.
	switch {
	case tracer.StartupProbe == nil:
		v.Addf("tracer sidecar %q has no startup probe, so container start order would not wait for it", tracer.Name)
	case tracer.StartupProbe.TCPSocket == nil:
		v.Addf("tracer sidecar %q startup probe is not a tcpSocket probe", tracer.Name)
	case tracer.StartupProbe.TCPSocket.Port != ssi.ReadyPort:
		v.Addf("tracer sidecar %q startup probe port = %d, want %d", tracer.Name, tracer.StartupProbe.TCPSocket.Port, ssi.ReadyPort)
	}
}

func verifyTracerSidecar(v *e2eshared.Violations, tmpl template, ssi *SSIExpectations) {
	wantName := tracerSidecarName(ssi.Language)
	tracer := findContainer(tmpl.Containers, wantName)
	if tracer == nil {
		v.Addf("tracer sidecar %q missing", wantName)
		return
	}

	if wantImage := ssi.tracerInitImage(); tracer.Image != wantImage {
		v.Addf("tracer sidecar image = %q, want %q", tracer.Image, wantImage)
	}
	if !tracer.hasMount(tracerVolumeName, tracerVolumePath) {
		v.Addf("tracer sidecar does not mount %q at %s", tracerVolumeName, tracerVolumePath)
	}
	// The image has no entrypoint of its own, so the copy script is part of the command the
	// module builds.
	if invocation := containerInvocation(tracer); !strings.Contains(invocation, "/datadog-init/copy-lib.sh "+tracerVolumePath) {
		v.Addf("tracer sidecar does not invoke copy-lib.sh against %s: %q", tracerVolumePath, invocation)
	}
	verifyTracerReadiness(v, tracer, ssi)

	vol, ok := findVolume(tmpl.Volumes, tracerVolumeName)
	if !ok {
		v.Addf("tracer volume %q missing", tracerVolumeName)
		return
	}
	if vol.EmptyDir == nil {
		v.Addf("tracer volume %q is not an emptyDir", tracerVolumeName)
		return
	}
	if vol.EmptyDir.Medium != ssi.VolumeMedium {
		v.Addf("tracer volume medium = %q, want %q", vol.EmptyDir.Medium, ssi.VolumeMedium)
	}
	wantLimit := "500Mi"
	if ssi.VolumeMedium == "DISK" {
		wantLimit = "10Gi"
	}
	if vol.EmptyDir.SizeLimit != wantLimit {
		v.Addf("tracer volume size_limit = %q, want %q", vol.EmptyDir.SizeLimit, wantLimit)
	}
}

// verifyClean asserts that the Cloud Run API reports the service as deleted, rather
// than accepting an unrelated authentication or transient failure as successful cleanup.
func verifyClean(describeErr error) error {
	var v e2eshared.Violations

	if describeErr == nil {
		v.Addf("service still exists after destroy")
	} else if status.Code(describeErr) != codes.NotFound {
		v.Addf("get service after destroy: want NotFound, got %v", describeErr)
	}

	return v.Err("uninstrumented (post-remove) contract violated")
}

func findVolume(volumes []volume, name string) (volume, bool) {
	for _, vol := range volumes {
		if vol.Name == name {
			return vol, true
		}
	}

	return volume{}, false
}

func findContainer(containers []container, name string) *container {
	for i := range containers {
		if containers[i].Name == name {
			return &containers[i]
		}
	}

	return nil
}

// containerInvocation flattens command and args so checks can look for a fragment without
// caring which of the two the module put it in.
func containerInvocation(c *container) string {
	return strings.Join(append(append([]string{}, c.Command...), c.Args...), " ")
}

func containsString(haystack []string, needle string) bool {
	for _, s := range haystack {
		if s == needle {
			return true
		}
	}

	return false
}

// copyFinishedMarker mirrors the marker path copy-lib.sh writes once the tracer is in place.
func copyFinishedMarker(language string) string {
	return fmt.Sprintf("%s/.%s-copy-finished", tracerVolumePath, tracerRepoName(language))
}
