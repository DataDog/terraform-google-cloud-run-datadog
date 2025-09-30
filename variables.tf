# Unless explicitly stated otherwise all files in this repository are licensed under the Apache-2.0 License.
# This product includes software developed at Datadog (https://www.datadoghq.com/) Copyright 2025 Datadog, Inc.

variable "datadog_api_key" {
  type        = string
  description = "Datadog API key"
  nullable    = false
}

variable "datadog_site" {
  type        = string
  description = "Datadog site"
  default     = "datadoghq.com"
  nullable    = false
  validation {
    condition = contains(
      [
        "datadoghq.com",
        "datadoghq.eu",
        "us5.datadoghq.com",
        "us3.datadoghq.com",
        "ddog-gov.com",
        "ap1.datadoghq.com",
        "ap2.datadoghq.com",
      ],
    var.datadog_site)
    error_message = "Invalid Datadog site. Valid options are: 'datadoghq.com', 'datadoghq.eu', 'us5.datadoghq.com', 'us3.datadoghq.com', 'ddog-gov.com', 'ap1.datadoghq.com', or 'ap2.datadoghq.com'."
  }
}

variable "datadog_service" {
  type        = string
  description = "Datadog Service tag, used for Unified Service Tagging."
  default     = null
}

variable "datadog_version" {
  type        = string
  description = "Datadog Version tag, used for Unified Service Tagging."
  default     = null
}

variable "datadog_env" {
  type        = string
  description = "Datadog Environment tag, used for Unified Service Tagging."
  default     = null
}

variable "datadog_tags" {
  type        = list(string)
  description = "Datadog tags"
  default     = null
  validation {
    condition = var.datadog_tags == null ? true : alltrue([for tag in var.datadog_tags :
    length(split(":", tag)) == 2 && alltrue([for part in split(":", tag) : length(part) > 0])])
    error_message = "Each tag must be a string with two parts separated by exactly one colon (e.g., 'key:value')."
  }
}

variable "datadog_enable_logging" {
  type        = bool
  description = "Enables log collection. Defaults to true."
  default     = true
}

variable "datadog_logging_path" {
  type        = string
  description = "Datadog logging path to be used for log collection. Ensure var.datadog_enable_logging is true. Must begin with path given in var.datadog_shared_volume.mount_path."
  default     = "/shared-volume/logs/*.log"
}

variable "datadog_log_level" {
  type        = string
  description = "Datadog agent's level of log output in Cloud Run UI, from most to least output: TRACE, DEBUG, INFO, WARN, ERROR, CRITICAL"
  default     = null
}

variable "datadog_shared_volume" {
  type = object({
    name       = string
    mount_path = string
    size_limit = optional(string)
  })
  description = "Datadog shared volume for log collection. Ensure var.datadog_enable_logging is true. Note: will always be of type empty_dir and in-memory. If a volume with this name is provided as part of var.template.volumes, it will be overridden."
  default = {
    name       = "shared-volume"
    mount_path = "/shared-volume"
  }
}

variable "datadog_sidecar" {
  type = object({
    image = optional(string, "gcr.io/datadoghq/serverless-init:latest")
    name  = optional(string, "datadog-sidecar")
    resources = optional(object({
      limits = optional(object({
        cpu    = optional(string, "1")
        memory = optional(string, "512Mi")
      }), null),
      }), { # default sidecar resources
      limits = {
        cpu    = "1"
        memory = "512Mi"
      }
    })
    startup_probe = optional(
      object({
        failure_threshold     = optional(number),
        initial_delay_seconds = optional(number),
        period_seconds        = optional(number),
        timeout_seconds       = optional(number),
      }),
      { # default startup probe
        failure_threshold     = 3
        period_seconds        = 10
        initial_delay_seconds = 0
        timeout_seconds       = 1
      }
    )
    health_port = optional(number, 5555) # DD_HEALTH_PORT
    env = optional(list(object({         # user-customizable env vars for Datadog agent configuration
      name  = string
      value = string
    })), null)
  })
  default = {
    image     = "gcr.io/datadoghq/serverless-init:latest"
    name      = "datadog-sidecar"
    resources = { limits = { cpu = "1", memory = "512Mi" } }
    startup_probe = {
      failure_threshold     = 3
      period_seconds        = 10
      initial_delay_seconds = 0
      timeout_seconds       = 1
    }
    health_port = 5555
  }
  description = <<DESCRIPTION
Datadog sidecar configuration. Nested attributes include:
- image - Image for version of Datadog agent to use.
- name - Name of the sidecar container.
- resources - Resources like for any cloud run container.
- startup_probe - Startup probe settings only for failure_threshold, initial_delay_seconds, period_seconds, timeout_seconds.
- health_port - Health port to start the startup probe.
- env_vars - List of environment variables with name and value fieldsfor customizing Datadog agent configuration, if any.
DESCRIPTION
}
