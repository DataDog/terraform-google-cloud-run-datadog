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
        "us2.ddog-gov.com",
        "ap1.datadoghq.com",
        "ap2.datadoghq.com",
        "uk1.datadoghq.com",
      ],
    var.datadog_site)
    error_message = "Invalid Datadog site. Valid options are: 'datadoghq.com', 'datadoghq.eu', 'us5.datadoghq.com', 'us3.datadoghq.com', 'ddog-gov.com', 'us2.ddog-gov.com', 'ap1.datadoghq.com', 'ap2.datadoghq.com', or 'uk1.datadoghq.com'."
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
- env_vars - List of environment variables with name and value fields for customizing Datadog agent configuration, if any.
DESCRIPTION
}

variable "datadog_apm_instrumentation" {
  type = object({
    language       = string
    tracer_version = optional(string, "latest")
    tracer_libc    = optional(string, "glibc")
    volume_medium  = optional(string, "MEMORY")
    ready_port     = optional(number, 18999)
  })
  description = <<-DESCRIPTION
Enables auto-instrumentation via a tracer sidecar.

- language - Tracer language. One of 'java', 'python', 'js', 'dotnet', 'php', 'ruby'.
- tracer_version - Tag of the dd-lib-<language>-init image to copy the tracer from. Pinned tags
  must be above java 1.65.1, js 6.10.0, python 4.13.0, dotnet 3.51.1, ruby 2.41.0, php 1.23.3
  For 'dotnet', pinned major versions below 3 are unsupported.
- tracer_libc - C library ABI of the application image: 'glibc' (default) or 'musl'.
  Selects the PHP loader path; Ruby does not support musl.
- volume_medium - emptyDir medium for the tracer volume: 'MEMORY' (default) or 'DISK'.
  DISK requires launch_stage BETA and a 10Gi size_limit.
- ready_port - Port the tracer sidecar listens on once the copy is verified. Must not
  collide with the agent sidecar health port or any app container port, since containers in
  an instance share a network namespace.
DESCRIPTION
  validation {
    condition = var.datadog_apm_instrumentation == null ? true : contains(
      [
        "java",
        "python",
        "js",
        "dotnet",
        "php",
        "ruby",
      ],
      var.datadog_apm_instrumentation.language,
    )
    error_message = "Invalid language. Valid options are: 'java', 'python', 'js', 'dotnet', 'php', and 'ruby'."
  }

  validation {
    condition = var.datadog_apm_instrumentation == null ? true : contains(
      ["glibc", "musl"],
      var.datadog_apm_instrumentation.tracer_libc,
    )
    error_message = "Invalid tracer_libc. Valid options are: 'glibc' and 'musl'."
  }

  validation {
    condition = var.datadog_apm_instrumentation == null ? true : contains(
      ["MEMORY", "DISK"],
      var.datadog_apm_instrumentation.volume_medium,
    )
    error_message = "Invalid volume_medium. Valid options are: 'MEMORY' and 'DISK'."
  }

  validation {
    condition = var.datadog_apm_instrumentation == null ? true : !(
      var.datadog_apm_instrumentation.language == "ruby" &&
      var.datadog_apm_instrumentation.tracer_libc == "musl"
    )
    error_message = "Ruby Single-Language SSI does not support musl. Use tracer_libc = \"glibc\", or instrument Ruby another way."
  }

  validation {
    # pinned .NET tracer majors below 3 use incompatible arch-specific paths.
    # Unpinned tags such as "latest" are allowed.
    condition = var.datadog_apm_instrumentation == null ? true : (
      var.datadog_apm_instrumentation.language != "dotnet" ? true : try(
        tonumber(regex("^v?(\\d+)(?:\\.|$)", var.datadog_apm_instrumentation.tracer_version)[0]) >= 3,
        true,
      )
    )
    error_message = "Unsupported .NET tracer_version: versions before 3.0 require architecture-specific package paths. Use tracer_version \"latest\" or a 3.x+ tag."
  }

  validation {
    # ensure selected tracer version is compatible. Older versions dont include probe-server in dd-lib-*-init image which is required for ssi
    condition = var.datadog_apm_instrumentation == null ? true : try(
      sum([
        for index, part in regex("^v?(\\d+)\\.(\\d+)\\.(\\d+)$", var.datadog_apm_instrumentation.tracer_version) :
        tonumber(part) * pow(1000, 2 - index)
        ]) > sum([
        for index, part in regex("^(\\d+)\\.(\\d+)\\.(\\d+)$", {
          java   = "1.65.1"
          js     = "6.10.0"
          python = "4.13.0"
          dotnet = "3.51.1"
          ruby   = "2.41.0"
          php    = "1.23.3"
        }[var.datadog_apm_instrumentation.language]) :
        tonumber(part) * pow(1000, 2 - index)
      ]),
      true,
    )
    error_message = "Unsupported tracer_version. Use tracer_version \"latest\", or a tag above java 1.65.1, js 6.10.0, python 4.13.0, dotnet 3.51.1, ruby 2.41.0, php 1.23.3."
  }

  validation {
    condition = var.datadog_apm_instrumentation == null ? true : (
      var.datadog_apm_instrumentation.ready_port >= 1024 &&
      var.datadog_apm_instrumentation.ready_port <= 65535
    )
    error_message = "Invalid ready_port. Must be between 1024 and 65535, since the container that listens on it runs unprivileged."
  }
  default = null
}
