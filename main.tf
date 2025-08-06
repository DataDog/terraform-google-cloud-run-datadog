variable "dd_api_key" {
  type = string
  description = "Datadog API key"
  nullable = false
}

variable "dd_site" {
  type = string
  description = "Datadog site"
  default = "datadoghq.com"
  nullable = false
}

variable "dd_service" {
  type = string
  description = "Datadog service, searchable tag to be used for logs and tracing."
  default = null
}

variable "dd_version" {
  type = string
  description = "Datadog version of your deployment to be used for tracing/metrics."
  default = null
}

variable "dd_env" {
  type = string
  description = "Datadog environment"
  default = null
}

variable "dd_tags" {
  type = list(string)
  description = "Datadog tags"
  default = null
}

variable "dd_enable_logging" {
  type = bool
  description = "Enables log collection. Defaults to true. Make sure to provide both shared_volume and logging_path."
  default = true
}

variable "dd_logging_path" {
  type = string
  description = "Datadog logging path to be used for log collection if dd_logs_injection is true."
  default = "/shared-volume/logs/*.log"
}

variable "dd_log_level" {
  type = string
  description = "Datadog log level"
  default = null
}

variable "dd_shared_volume" {
  type = object({
    name = string
    mount_path = string
  })
  description = "Datadog shared volume for log collection. Note: will always be of type empty_dir and in-memory. If a volume with this name is provided as part of var.template.volumes, it will be overridden."
  default = {
    name = "shared-volume"
    mount_path = "/shared-volume"
  }
}

# TODO: DD_TRACE_ENABLED (does not work), ask about fips,  ..llmobs?

variable "dd_sidecar" {
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
        cpu = "1"
        memory = "512Mi"
      }
    })
    health_port  = optional(number, 5555) # DD_HEALTH_PORT
    

  })
  description = "Datadog sidecar configuration"
}

locals{
  dd_logging_vol = { #the shared volume for logging which each container can write their Datadog logs to
    name = var.dd_shared_volume.name
    empty_dir = {
      medium = "MEMORY"
    }
  }

  # User-check 1: use this to override user's var.template.volumes and remove the shared volume if shared_volume already exists and logging is enabled, else keep user's volumes
  volumes_without_shared_volume = var.dd_enable_logging == true ? [ 
    for v in coalesce(var.template.volumes, []) : v
    if v.name != var.dd_shared_volume.name
    ] : coalesce(var.template.volumes, [])
 
 # flag if logging is enabled and shared_volume is already in the template volumes (name of volume exists)
  shared_volume_already_exists = length(var.template.volumes) != length(local.volumes_without_shared_volume)

  # User-check 2: check if sidecar container already exists and remove it from the var.template.containers list if it does (to be overridden by module's instantiation)
  containers_without_sidecar = [
    for c in coalesce(var.template.containers, []) : c
    if !strcontains(c.image, "gcr.io/datadoghq/serverless-init")
  ]

  # flag if sidecar container already exists
  already_has_sidecar = length(coalesce(var.template.containers, [])) != length(local.containers_without_sidecar)

  # User-check 3: check for each provided container (ignoring sidecar if provided) the volume mounts and if logging is enabled, exclude all volume mounts with same name OR path as the shared volume
  all_volume_mounts = flatten([
    for c in coalesce(local.containers_without_sidecar, []) :
    coalesce(c.volume_mounts, [])
  ])

  filtered_volume_mounts = var.dd_enable_logging == true ? [ #filter out volume mounts with same name or path as the shared volume only if logging is enabled
    for vm in local.all_volume_mounts :
    vm if !(vm.name == var.dd_shared_volume.name || vm.mount_path == var.dd_shared_volume.mount_path)
  ] : local.all_volume_mounts
  
  overlapping_volume_mounts = length(local.filtered_volume_mounts) != length(local.all_volume_mounts)


  #Sidecar env vars
  required_sidecar_env_vars = [ #api, site, service, and healthport are always existing
    {
      env_name = "DD_API_KEY"
      env_value = var.dd_api_key
    },
    {
      env_name = "DD_SITE"
      env_value = var.dd_site
    },
    {
      env_name = "DD_SERVICE"
      env_value = var.dd_service != null ? var.dd_service : var.name # defaults to name of the cloud run service
    },
    {
      env_name = "DD_HEALTH_PORT"
      env_value = tostring(var.dd_sidecar.health_port)
    }
  ]
  all_sidecar_env_vars = concat(
    local.required_sidecar_env_vars,
    var.dd_version != null ? [{
      env_name = "DD_VERSION"
      env_value = var.dd_version
    }] : [],
    var.dd_env != null ? [{
      env_name = "DD_ENV"
      env_value = var.dd_env
    }] : [],
    var.dd_tags != null ? [
      {
        env_name  = "DD_TAGS"
        env_value = join(",", var.dd_tags)
      }
    ] : [],
    var.dd_enable_logging == true ? [{ # always enable logs injection if logging is enabled
      env_name = "DD_LOGS_INJECTION"
      env_value = var.dd_enable_logging ? "true" : "false"
    }] : [],
    var.dd_log_level != null ? [{
      env_name = "DD_LOG_LEVEL"
      env_value = var.dd_log_level
    }] : [],
    var.dd_enable_logging == true ? [{
      env_name = "DD_SERVERLESS_LOG_PATH"
      env_value = var.dd_logging_path
    }] : [],
  )

}

check "logging_volume_already_exists" {
  assert {
    condition = local.shared_volume_already_exists == false
    error_message = "Datadog log collection is enabled and a volume with the name \"${var.dd_shared_volume.name}\" already exists in the var.template.volumes list. This module will override the existing volume with the settings provided in var.datadog_shared_volume and use it for Datadog log collection. To disable log collection, set var.datadog_enable_logging to false."
  }
}

check "sidecar_already_exists" {
  assert {
    condition = local.already_has_sidecar == false
    error_message = "A sidecar container using the Datadog agent image \"gcr.io/datadoghq/serverless-init...\" already exists in the var.template.containers list. This module will override the existing container(s) using this image with the settings provided in var.datadog_sidecar."
  }
}

check "volume_mounts_share_names_and_or_paths" {
  assert {
    condition = local.overlapping_volume_mounts == false
    error_message = "Logging is enabled, and user-inputted volume mounts overlap with values for var.datadog_shared_volume. This module will remove the following containers' volume_mounts sharing a name or path as the Datadog shared volume: ${join(",",[for vm in local.all_volume_mounts : format("\n%s:%s", vm.name, vm.mount_path)if !contains(local.filtered_volume_mounts, vm)])}.\nThis module will add the Datadog volume_mount instead to all containers."
  }
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
  labels               = merge({service = var.dd_service != null ? var.dd_service : var.name}, var.labels) # Default service tag value to cloud run resource name if not provided
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
      for_each = local.containers_without_sidecar != null ? local.containers_without_sidecar : []
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
          name = "DD_SERVICE"
          value = var.dd_service != null ? var.dd_service : var.name # defaults to name of the cloud run service
        }
        dynamic "volume_mounts" { # add the shared volume to the container if logging is enabled
          for_each = var.dd_enable_logging == true ? [true] : []
          content {
            name       = var.dd_shared_volume.name
            mount_path = var.dd_shared_volume.mount_path
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

      # User-check 3: check for each provided container the volume mounts and if logging is enabled and the shared volume is an input, do not mount it again
      dynamic "volume_mounts" {
        for_each = [for vm in containers.value.volume_mounts : vm if contains(local.filtered_volume_mounts, vm)]
          content {
            mount_path = volume_mounts.value.mount_path
            name       = volume_mounts.value.name
          }
        }
      }
    }

    # Create the sidecar container
    # NOTE: User can have provided shared volume, a sidecar container, or logging details to pass into the module and module overrides it, instruments everything
    containers {
      name = var.dd_sidecar.name
      image = var.dd_sidecar.image
      dynamic "resources" {
        for_each = var.dd_sidecar.resources != null ? [true] : []
        content {
          limits = var.dd_sidecar.resources.limits
        }
      }
      dynamic "volume_mounts" { # add the shared volume to the sidecar if logging is enabled
        for_each = var.dd_enable_logging == true ? [true] : []
        content {
          name = var.dd_shared_volume.name
          mount_path = var.dd_shared_volume.mount_path
        }
      }

      startup_probe {
        # TODO: add user customization
        tcp_socket {
          port = var.dd_sidecar.health_port
        }
        initial_delay_seconds = 0
        period_seconds = 10
        failure_threshold = 3
        timeout_seconds = 1
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
      for_each = local.volumes_without_shared_volume
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

    # If dd_enable_logging is true, add the shared volume to the template volumes
    dynamic "volumes" {
      for_each = var.dd_enable_logging == true ? [true] : []
      content {
        name = var.dd_shared_volume.name
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
