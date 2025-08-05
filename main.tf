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
}

variable "datadog_enable_logging" {
  type        = bool
  description = "Enables log collection. Defaults to true. Make sure to provide both shared_volume and logging_path."
  default     = true
}

variable "datadog_logging_path" {
  type        = string
  description = "Datadog logging path to be used for logging if datadog_logs_injection is true."
  default     = "/shared-volume/logs/*.log"
}

variable "datadog_log_level" {
  type        = string
  description = "Datadog log level"
  default     = null
}

variable "datadog_shared_volume" {
  type = object({
    name       = string
    mount_path = string
  })
  description = "Datadog shared volume"
  default = {
    name       = "shared-volume"
    mount_path = "/shared-volume"
  }
}

# trace_enabled = optional(bool, true) #DD_TRACE_ENABLED
# TODO: DD_TRACE_ENABLED, ask about fips,  ..llmobs?

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
    health_port = optional(number, 5555) # DD_HEALTH_PORT


  })
  description = "Datadog sidecar configuration"
}

locals {
  datadog_logging_vol = { #the shared volume for logging which each container can write their Datadog logs to
    name = var.datadog_shared_volume.name
    empty_dir = {
      medium = "MEMORY"
    }
  }

  # TODO: figure out how to handle case if shared_volume is already in the template volumes and type-safety the tuple conversion
  # TODO: what if user has a dd-sidecar container already?

  #Sidecar env vars
  required_sidecar_env_vars = [ #api, site, service, and healthport are always existing
    {
      env_name  = "DD_API_KEY"
      env_value = var.datadog_api_key
    },
    {
      env_name  = "DD_SITE"
      env_value = var.datadog_site
    },
    {
      env_name  = "DD_SERVICE"
      env_value = var.datadog_service != null ? var.datadog_service : var.name # defaults to name of the cloud run service
    },
    {
      env_name  = "DD_HEALTH_PORT"
      env_value = tostring(var.datadog_sidecar.health_port)
    }
  ]
  all_sidecar_env_vars = concat(
    local.required_sidecar_env_vars,
    var.datadog_version != null ? [{
      env_name  = "DD_VERSION"
      env_value = var.datadog_version
    }] : [],
    var.datadog_env != null ? [{
      env_name  = "DD_ENV"
      env_value = var.datadog_env
    }] : [],
    var.datadog_tags != null ? [
      {
        env_name  = "DD_TAGS"
        env_value = join(",", var.datadog_tags)
      }
    ] : [],
    var.datadog_enable_logging == true ? [{ # always enable logs injection if logging is enabled
      env_name  = "DD_LOGS_INJECTION"
      env_value = var.datadog_enable_logging ? "true" : "false"
    }] : [],
    var.datadog_log_level != null ? [{
      env_name  = "DD_LOG_LEVEL"
      env_value = var.datadog_log_level
    }] : [],
    var.datadog_enable_logging == true ? [{
      env_name  = "DD_SERVERLESS_LOG_PATH"
      env_value = var.datadog_logging_path
    }] : [],
  )

}

resource "google_cloud_run_v2_service" "this" {
  annotations          = var.annotations
  client               = var.client
  client_version       = var.client_version
  custom_audiences     = var.custom_audiences
  deletion_protection  = var.deletion_protection
  description          = var.description
  ingress              = var.ingress
  invoker_iam_disabled = var.invoker_iam_disabled
  labels               = merge({ service = var.datadog_service != null ? var.datadog_service : var.name }, var.labels) # Default service tag value to cloud run resource name if not provided
  launch_stage         = var.launch_stage
  location             = var.location
  name                 = var.name
  project              = var.project
  dynamic "binary_authorization" {
    for_each = var.binary_authorization != null ? [true] : []
    content {
      breakglass_justification = var.binary_authorization.breakglass_justification
      policy                   = var.binary_authorization.policy
      use_default              = var.binary_authorization.use_default
    }
  }
  dynamic "build_config" {
    for_each = var.build_config != null ? [true] : []
    content {
      base_image               = var.build_config.base_image
      enable_automatic_updates = var.build_config.enable_automatic_updates
      environment_variables    = var.build_config.environment_variables
      function_target          = var.build_config.function_target
      image_uri                = var.build_config.image_uri
      service_account          = var.build_config.service_account
      source_location          = var.build_config.source_location
      worker_pool              = var.build_config.worker_pool
    }
  }
  dynamic "scaling" {
    for_each = var.scaling != null ? [true] : []
    content {
      manual_instance_count = var.scaling.manual_instance_count
      min_instance_count    = var.scaling.min_instance_count
      scaling_mode          = var.scaling.scaling_mode
    }
  }
  template {
    annotations                      = var.template.annotations
    encryption_key                   = var.template.encryption_key
    execution_environment            = var.template.execution_environment
    gpu_zonal_redundancy_disabled    = var.template.gpu_zonal_redundancy_disabled
    labels                           = var.template.labels
    max_instance_request_concurrency = var.template.max_instance_request_concurrency
    revision                         = var.template.revision
    service_account                  = var.template.service_account
    session_affinity                 = var.template.session_affinity
    timeout                          = var.template.timeout
    dynamic "containers" {
      for_each = var.template.containers != null ? var.template.containers : []
      content {
        args           = containers.value.args
        base_image_uri = containers.value.base_image_uri
        command        = containers.value.command
        depends_on     = containers.value.depends_on
        image          = containers.value.image
        name           = containers.value.name
        working_dir    = containers.value.working_dir

        # User-provided resource environment variables
        dynamic "env" {
          for_each = containers.value.env != null ? containers.value.env : []
          content {
            name  = env.value.name
            value = env.value.value
            dynamic "value_source" {
              for_each = env.value.value_source != null ? [true] : []
              content {
                dynamic "secret_key_ref" {
                  for_each = env.value.value_source.secret_key_ref != null ? [true] : []
                  content {
                    secret  = env.value.value_source.secret_key_ref.secret
                    version = env.value.value_source.secret_key_ref.version
                  }
                }
              }
            }
          }
        }

        # NOTE: Assumes user has not provided any sidecar container, shared volume, or logging details to pass into the module and module is instrumenting everything
        # Configure DD_SERVICE and volume mounts on application container
        env {
          name  = "DD_SERVICE"
          value = var.datadog_service != null ? var.datadog_service : var.name # defaults to name of the cloud run service
        }
        dynamic "volume_mounts" { # add the shared volume to the container if logging is enabled
          for_each = var.datadog_enable_logging == true ? [true] : []
          content {
            name       = var.datadog_shared_volume.name
            mount_path = var.datadog_shared_volume.mount_path
          }
        }

        dynamic "liveness_probe" {
          for_each = containers.value.liveness_probe != null ? [true] : []
          content {
            failure_threshold     = containers.value.liveness_probe.failure_threshold
            initial_delay_seconds = containers.value.liveness_probe.initial_delay_seconds
            period_seconds        = containers.value.liveness_probe.period_seconds
            timeout_seconds       = containers.value.liveness_probe.timeout_seconds
            dynamic "grpc" {
              for_each = containers.value.liveness_probe.grpc != null ? [true] : []
              content {
                port    = containers.value.liveness_probe.grpc.port
                service = containers.value.liveness_probe.grpc.service
              }
            }
            dynamic "http_get" {
              for_each = containers.value.liveness_probe.http_get != null ? [true] : []
              content {
                path = containers.value.liveness_probe.http_get.path
                port = containers.value.liveness_probe.http_get.port
                dynamic "http_headers" {
                  for_each = containers.value.liveness_probe.http_get.http_headers != null ? containers.value.liveness_probe.http_get.http_headers : []
                  content {
                    name  = http_headers.value.name
                    value = http_headers.value.value
                  }
                }
              }
            }
            dynamic "tcp_socket" {
              for_each = containers.value.liveness_probe.tcp_socket != null ? [true] : []
              content {
                port = containers.value.liveness_probe.tcp_socket.port
              }
            }
          }
        }
        dynamic "ports" {
          for_each = containers.value.ports != null ? [true] : []
          content {
            container_port = containers.value.ports.container_port
            name           = containers.value.ports.name
          }
        }
        dynamic "resources" {
          for_each = containers.value.resources != null ? [true] : []
          content {
            cpu_idle          = containers.value.resources.cpu_idle
            limits            = containers.value.resources.limits
            startup_cpu_boost = containers.value.resources.startup_cpu_boost
          }
        }
        dynamic "startup_probe" {
          for_each = containers.value.startup_probe != null ? [true] : []
          content {
            failure_threshold     = containers.value.startup_probe.failure_threshold
            initial_delay_seconds = containers.value.startup_probe.initial_delay_seconds
            period_seconds        = containers.value.startup_probe.period_seconds
            timeout_seconds       = containers.value.startup_probe.timeout_seconds
            dynamic "grpc" {
              for_each = containers.value.startup_probe.grpc != null ? [true] : []
              content {
                port    = containers.value.startup_probe.grpc.port
                service = containers.value.startup_probe.grpc.service
              }
            }
            dynamic "http_get" {
              for_each = containers.value.startup_probe.http_get != null ? [true] : []
              content {
                path = containers.value.startup_probe.http_get.path
                port = containers.value.startup_probe.http_get.port
                dynamic "http_headers" {
                  for_each = containers.value.startup_probe.http_get.http_headers != null ? containers.value.startup_probe.http_get.http_headers : []
                  content {
                    name  = http_headers.value.name
                    value = http_headers.value.value
                  }
                }
              }
            }
            dynamic "tcp_socket" {
              for_each = containers.value.startup_probe.tcp_socket != null ? [true] : []
              content {
                port = containers.value.startup_probe.tcp_socket.port
              }
            }
          }
        }
        dynamic "volume_mounts" {
          for_each = containers.value.volume_mounts != null ? containers.value.volume_mounts : []
          content {
            mount_path = volume_mounts.value.mount_path
            name       = volume_mounts.value.name
          }
        }
      }
    }

    # Create the sidecar container
    # NOTE: Assumes user has not provided any sidecar container, shared volume, or logging details to pass into the module and module is instrumenting everything
    containers {
      name  = var.datadog_sidecar.name
      image = var.datadog_sidecar.image
      dynamic "resources" {
        for_each = var.datadog_sidecar.resources != null ? [true] : []
        content {
          limits = var.datadog_sidecar.resources.limits
        }
      }
      dynamic "volume_mounts" { # add the shared volume to the sidecar if logging is enabled
        for_each = var.datadog_enable_logging == true ? [true] : []
        content {
          name       = var.datadog_shared_volume.name
          mount_path = var.datadog_shared_volume.mount_path
        }
      }

      startup_probe {
        # TODO: add user customization
        tcp_socket {
          port = var.datadog_sidecar.health_port
        }
        initial_delay_seconds = 0
        period_seconds        = 10
        failure_threshold     = 3
        timeout_seconds       = 1
      }

      # all env variables
      dynamic "env" {
        for_each = toset(local.all_sidecar_env_vars)
        content {
          name  = env.value.env_name
          value = env.value.env_value
        }
      }
    }

    dynamic "node_selector" {
      for_each = var.template.node_selector != null ? [true] : []
      content {
        accelerator = var.template.node_selector.accelerator
      }
    }
    dynamic "scaling" {
      for_each = var.template.scaling != null ? [true] : []
      content {
        max_instance_count = var.template.scaling.max_instance_count
        min_instance_count = var.template.scaling.min_instance_count
      }
    }
    dynamic "volumes" {
      for_each = var.template.volumes != null ? var.template.volumes : []
      content {
        name = volumes.value.name
        dynamic "cloud_sql_instance" {
          for_each = volumes.value.cloud_sql_instance != null ? [true] : []
          content {
            instances = volumes.value.cloud_sql_instance.instances
          }
        }
        dynamic "empty_dir" {
          for_each = volumes.value.empty_dir != null ? [true] : []
          content {
            medium     = volumes.value.empty_dir.medium
            size_limit = volumes.value.empty_dir.size_limit
          }
        }
        dynamic "gcs" {
          for_each = volumes.value.gcs != null ? [true] : []
          content {
            bucket    = volumes.value.gcs.bucket
            read_only = volumes.value.gcs.read_only
          }
        }
        dynamic "nfs" {
          for_each = volumes.value.nfs != null ? [true] : []
          content {
            path      = volumes.value.nfs.path
            read_only = volumes.value.nfs.read_only
            server    = volumes.value.nfs.server
          }
        }
        dynamic "secret" {
          for_each = volumes.value.secret != null ? [true] : []
          content {
            default_mode = volumes.value.secret.default_mode
            secret       = volumes.value.secret.secret
            dynamic "items" {
              for_each = volumes.value.secret.items != null ? volumes.value.secret.items : []
              content {
                mode    = items.value.mode
                path    = items.value.path
                version = items.value.version
              }
            }
          }
        }
      }
    }

    # NOTE: Assumes user has not provided any sidecar container, shared volume, or logging details to pass into the module and module is instrumenting everything
    # If enable_logging is true, add the shared volume to the template volumes
    dynamic "volumes" {
      for_each = var.datadog_enable_logging == true ? [true] : []
      content {
        name = var.datadog_shared_volume.name
        empty_dir {
          medium = "MEMORY"
        }
      }
    }


    dynamic "vpc_access" {
      for_each = var.template.vpc_access != null ? [true] : []
      content {
        connector = var.template.vpc_access.connector
        egress    = var.template.vpc_access.egress
        dynamic "network_interfaces" {
          for_each = var.template.vpc_access.network_interfaces != null ? var.template.vpc_access.network_interfaces : []
          content {
            network    = network_interfaces.value.network
            subnetwork = network_interfaces.value.subnetwork
            tags       = network_interfaces.value.tags
          }
        }
      }
    }
  }
  dynamic "timeouts" {
    for_each = var.timeouts != null ? [true] : []
    content {
      create = var.timeouts.create
      delete = var.timeouts.delete
      update = var.timeouts.update
    }
  }
  dynamic "traffic" {
    for_each = var.traffic != null ? var.traffic : []
    content {
      percent  = traffic.value.percent
      revision = traffic.value.revision
      tag      = traffic.value.tag
      type     = traffic.value.type
    }
  }
}
