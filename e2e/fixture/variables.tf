# Unless explicitly stated otherwise all files in this repository are licensed under the Apache-2.0 License.
# This product includes software developed at Datadog (https://www.datadoghq.com/) Copyright 2026 Datadog, Inc.

variable "project" {
  type        = string
  description = "GCP project ID to deploy the ephemeral Cloud Run service into."
  nullable    = false
}

variable "region" {
  type        = string
  description = "GCP region for the google provider and the Cloud Run service location."
  nullable    = false
}

variable "name" {
  type        = string
  description = "Cloud Run service name. Carries the one-e2e-<tool>-<platform>-<runid> hygiene prefix set by the test."
  nullable    = false
}

variable "workload_image" {
  type        = string
  description = "Prebuilt prod self-monitoring workload image (the app under instrumentation). Should be pinned by digest."
  nullable    = false
}

variable "workload_memory" {
  type        = string
  description = "Memory limit for the workload container. Raised for JVM workloads, which need more headroom than the scripting runtimes."
  default     = "512Mi"
  nullable    = false
}

variable "sidecar_image" {
  type        = string
  description = "Datadog serverless-init sidecar image, pinned by digest so failures blame the module, not upstream."
  nullable    = false
}

variable "datadog_api_key" {
  type        = string
  description = "Datadog API key wired into the sidecar."
  nullable    = false
  sensitive   = true
}

variable "datadog_site" {
  type        = string
  description = "Datadog site the sidecar reports to."
  nullable    = false
}

variable "datadog_service" {
  type        = string
  description = "Unified Service Tagging service. Set to the unique run service name so telemetry is filterable by run."
  nullable    = false
}

variable "datadog_env" {
  type        = string
  description = "Unified Service Tagging env tag asserted on ingested telemetry."
  nullable    = false
}

variable "datadog_version" {
  type        = string
  description = "Unified Service Tagging version tag asserted on ingested telemetry."
  nullable    = false
}

variable "datadog_apm_instrumentation" {
  type = object({
    language       = string
    tracer_version = optional(string, "latest")
    volume_medium  = optional(string, "MEMORY")
    ready_port     = optional(number, 18999)
  })
  description = "When set, enables Single-Language SSI (tracer sidecar + language env injection)."
  default     = null
}

variable "build_config" {
  type = object({
    function_target          = string
    image_uri                = optional(string)
    base_image               = optional(string)
    enable_automatic_updates = optional(bool)
  })
  description = "When set, configures Cloud Run Functions build_config (used by the node-function example)."
  default     = null
}

variable "base_image_uri" {
  type        = string
  description = "Optional base_image_uri for the workload container (Cloud Run Functions)."
  default     = null
}

variable "run_id" {
  type        = string
  description = "Unique run id marker. Emitted as the one_e2e_run_id Datadog tag for run-scoped telemetry queries."
  nullable    = false
}

variable "created_ts" {
  type        = string
  description = "Unix timestamp set atomically at creation as the one_e2e_created freshness label for the sweeper."
  nullable    = false
}
