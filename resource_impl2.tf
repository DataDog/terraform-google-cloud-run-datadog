
resource "google_cloud_run_v2_service" "old" {
  annotations          = var.annotations
  client               = var.client
  client_version       = var.client_version
  custom_audiences     = var.custom_audiences
  deletion_protection  = var.deletion_protection
  description          = var.description
  ingress              = var.ingress
  invoker_iam_disabled = var.invoker_iam_disabled
  labels               = merge({ service = local.datadog_service }, var.labels) # Default service tag value to cloud run resource name if not provided
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
          for_each = containers.value.env != null ? [for env in containers.value.env : env if env.name != "DD_SERVERLESS_LOG_PATH"] : [] # will ignore user-provided DD_SERVERLESS_LOG_PATH env var for the var.datadog_logging_path value
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

        # if user provides a container-level DD_SERVICE env var, we use the more specific value, else we use service computed by module in local.datadog_service
        dynamic "env" {
          for_each = contains([for env in coalesce(containers.value.env, []) : env.name], "DD_SERVICE") ? [] : [true]
          content {
            name  = "DD_SERVICE"
            value = local.datadog_service
          }
        }

        # if user provides a container-level DD_LOGS_INJECTION env var, we use the more specific value (and should not set DD_LOGS_INJECTION here), 
        # if logging is not enabled, DD_LOGS_INJECTION should not be set
        dynamic "env" {
          for_each = (contains([for env in coalesce(containers.value.env, []) : env.name], "DD_LOGS_INJECTION") || var.datadog_enable_logging == false) ? [] : [true]
          content {
            name  = "DD_LOGS_INJECTION"
            value = "true"
          }
        }

        # also add the same dd_serverless_log_path (var.datadog_logging_path) env var to user containers as for sidecar so logs cannot be dropped
        dynamic "env" {
          for_each = var.datadog_enable_logging == true ? [true] : []
          content {
            name  = "DD_SERVERLESS_LOG_PATH"
            value = var.datadog_logging_path
          }
        }

        # Always adds module-computed volume mount on application container
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

        # User-check 3: check for each provided container the volume mounts and if logging is enabled and the shared volume is an input, do not mount it again
        dynamic "volume_mounts" {
          for_each = [for vm in coalesce(containers.value.volume_mounts, []) : vm if contains(local.filtered_volume_mounts, vm)]
          content {
            mount_path = volume_mounts.value.mount_path
            name       = volume_mounts.value.name
          }
        }
      }
    }

    # Create the sidecar container
    # NOTE: User can have provided a sidecar container but module overrides it, instruments everything
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
        failure_threshold     = var.datadog_sidecar.startup_probe.failure_threshold
        initial_delay_seconds = var.datadog_sidecar.startup_probe.initial_delay_seconds
        period_seconds        = var.datadog_sidecar.startup_probe.period_seconds
        timeout_seconds       = var.datadog_sidecar.startup_probe.timeout_seconds
        tcp_socket {
          port = var.datadog_sidecar.health_port
        }
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
      for_each = var.datadog_enable_logging == true ? [true] : []
      content {
        name = var.datadog_shared_volume.name
        empty_dir {
          medium     = "MEMORY"
          size_limit = var.datadog_shared_volume.size_limit
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
