variable "dd_api_key" {
  type = string
  description = "Datadog API key"
}

variable "dd_site" {
  type = string
  description = "Datadog site"
  default = "datadoghq.com"
}

variable "dd_service" {
  type = string
  description = "Datadog service, searchable tag to be used for logs and tracing"
  default = null
}

variable "dd_version" {
  type = string
  description = "Datadog version of your deployment to be used for tracing/metrics"
  default = null
}

variable "dd_env" {
  type = string
  description = "Datadog environment"
  default = null
}

variable "dd_tags" {
  type = string
  description = "Datadog tags"
  default = null
}

variable "dd_source" {
  type = string
  description = "Datadog source"
  default = null
}

variable "dd_logs_injection" {
  type = bool
  description = "Datadog logs injection, default true, will inject logs to Datadog dashboard, make sure to provide both shared_volume and logging_path"
  default = true
}

variable "dd_logging_path" {
  type = string
  description = "Datadog logging path to be used for logging if dd_logs_injection is true"
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
  description = "Datadog shared volume"
  default = {
    name = "shared-volume"
    mount_path = "/shared-volume"
  }
}

# trace_enabled = optional(bool, true) #DD_TRACE_ENABLED
# TODO: DD_TRACE_ENABLED, ask about fips,  ..llmobs?

variable "dd_sidecar" {
  type = object({
    build_from_scratch = bool # if true, will build the sidecar image because user doesn't provide any sidecar, tracing, or logging details in their current deployment yet
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

  # TODO: figure out how to handle case if shared_volume is already in the template volumes and type-safety the tuple conversion
  # cur_volumes = var.template.volumes != null ? var.template.volumes : []
  # without_sidecar_volumes = [for vol in local.cur_volumes: vol if vol.name != local.dd_logging_vol.name]
  
  # new_volumes = var.datadog.logs_injection ? concat( #add the shared volume to the template volumes if logs_injection is true
  #   local.without_sidecar_volumes,
  #   [local.dd_logging_vol]
  # ) : [for v in local.cur_volumes: v]

  #sidecar env vars
  # sidecar_env_vars =[for env_var in [{ # DEBUG
  #   ekey = "DD_API_KEY"
  #   evalue = var.datadog.api_key # Required = API key and site
  #   },
  #   {ekey = "DD_SITE",
  #   evalue = var.datadog.site},
  #   {ekey = "DD_SERVICE",
  #   evalue = var.datadog.service != null ? var.datadog.service : var.name # defaults to name of the cloud run service
  #   }, 
    # {key = "DD_VERSION",
    # value = var.datadog.version != null ? var.datadog.version : null},
    # var.datadog.env != null ? { # optional env
    #   key = "DD_ENV",
    #   value = var.datadog.env
    # } : {key: null, value: null},
    # var.datadog.tags != null ? { # optional tags
    #   key = "DD_TAGS",
    #   value = var.datadog.tags
    # } : {key: null, value: null},
    # var.datadog.logs_injection != null ? { # optional logs_injection, TODO: update if needed
    #   key = "DD_LOGS_INJECTION",
    #   value = var.datadog.logs_injection ? "true" : "false"
    # } : {key: null, value: null},
    # var.datadog.log_level != null ? { # optional log_level
    #   key = "DD_LOG_LEVEL",
    #   value = var.datadog.log_level
    # } : {key: null, value: null},
    # var.datadog.logs_injection == true ? { # optional logging_path, only if logs_injection is true
    #   key = "DD_SERVERLESS_LOG_PATH",
    #   value = var.datadog.logging_path
    # } : {key: null, value: null}
  # ]: env_var != null && env_var.evalue != null]

  # TODO: what if user has a dd-sidecar container already?
  # non_sidecar_containers = var.template.containers != null ? [for container in var.template.containers : container if container.name != var.datadog.sidecar_name] : []

}

check "no_existing_sidecar"{
  # current assumption is user leaves it completely to our module instrument with Datadog, has no shared volume for logging or declaration for sidecar container yet
  assert{
    condition = var.dd_sidecar.build_from_scratch == true
    error_message = "User must provide build_from_scratch = true and ensure they have no sidecar container, shared volume, or logging details passed into the module"
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
      # name                     = var.build_config.name
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
        dynamic "env" { #for each  container, if instrumenting with datadog and a service name is provided, add this as a 
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

        #### Start of manual instrumentation insertion ####
        # Datadog environment variables, only service required
        env {
          name = "DD_SERVICE"
          value = var.dd_service != null ? var.dd_service : var.name # defaults to name of the cloud run service
        }
        dynamic "volume_mounts" { # add the shared volume to the container if logs_injection is true
          for_each = var.dd_logs_injection == true ? [true] : []
          content {
            name       = var.dd_shared_volume.name
            mount_path = var.dd_shared_volume.mount_path
          }
        }
        #### End of manual instrumentation insertion ####
        
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

    # makes the sidecar container
    containers {
      name = var.dd_sidecar.name
      image = var.dd_sidecar.image
      dynamic "resources" {
        for_each = var.dd_sidecar.resources != null ? [true] : []
        content {
          limits = var.dd_sidecar.resources.limits
          # cpu_idle = var.datadog.sidecar_resources.cpu_idle
          # startup_cpu_boost = var.datadog.sidecar_resources.startup_cpu_boost
        }
      }
      dynamic "volume_mounts" {
        for_each = var.dd_logs_injection == true ? [true] : []
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
      # dynamic "env" {
      #   for_each = toset(local.sidecar_env_vars)
      #   content {
      #     name  = env.value.ekey # DEBUG
      #     value = env.value.evalue
      #   }
      # }
      env {
        name = "DD_API_KEY"
        value = var.dd_api_key
      }
      env {
        name = "DD_SITE"
        value = var.dd_site
      }
      env {
        name = "DD_SERVICE"
        value = var.dd_service != null ? var.dd_service : var.name # defaults to name of the cloud run service
      }
      dynamic "env" {
        for_each = var.dd_version != null ? [true] : []
        content {
          name = "DD_VERSION"
          value = var.dd_version
        }
      }
      dynamic "env" {
        for_each = var.dd_env != null ? [true] : []
        content {
          name = "DD_ENV"
          value = var.dd_env
        }
      }
      dynamic "env" {
        for_each = var.dd_tags != null ? [true] : []
        content {
          name = "DD_TAGS"
          value = var.dd_tags
        }
      }
      dynamic "env" {
        for_each = var.dd_logs_injection != null ? [true] : []
        content {
          name = "DD_LOGS_INJECTION"
          value = var.dd_logs_injection ? "true" : "false"
        }
      }
      dynamic "env" {
        for_each = var.dd_log_level != null ? [true] : []
        content {
          name = "DD_LOG_LEVEL"
          value = var.dd_log_level
        }
      }
      dynamic "env" {
        for_each = var.dd_logs_injection == true ? [true] : []
        content {
          name = "DD_SERVERLESS_LOG_PATH"
          value = var.dd_logging_path
        }
      }
      env {
        name = "DD_HEALTH_PORT"
        value = tostring(var.dd_sidecar.health_port)
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

    # MANUAL INSTRUMENTATION INSERTION: add the shared volume to the template volumes if logs_injection is true
    dynamic "volumes" {
      for_each = var.dd_logs_injection == true ? [true] : []
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
