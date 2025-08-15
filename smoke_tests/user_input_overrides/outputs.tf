# output "cloud_run_service_name_logging_enabled" {
#   description = "Name of the Cloud Run service found on Datadog Serverless Monitoring."
#   value = module.logging_enabled.name
# }

# output "service_containers_logging_enabled" {
#   description = "List of containers in the Cloud Run service."
#   value = module.logging_enabled.template[0].containers
# }

# output "service_volumes_logging_enabled" {
#   description = "List of volumes in the Cloud Run service."
#   value = module.logging_enabled.template[0].volumes
# }

# output "ignored_volume_mounts_logging_enabled" {
#   description = "List of container volume_mounts that share name or mount_path with the Datadog shared volume and are not added to the Cloud Run service when logging is enabled."
#   value = module.logging_enabled.ignored_volume_mounts
# }

# output "ignored_containers_logging_enabled" {
#   description = "List of containers that are ignored by the module."
#   value = module.logging_enabled.ignored_containers
# }

# output "ignored_volumes_logging_enabled" {
#   description = "List of volumes that are ignored by the module."
#   value = module.logging_enabled.ignored_volumes
# }

# output "cloud_run_service_name_logging_disabled" {
#   description = "Name of the Cloud Run service found on Datadog Serverless Monitoring."
#   value = module.logging_disabled.name
# }

# output "service_containers_logging_disabled" {
#   description = "List of containers in the Cloud Run service."
#   value = module.logging_disabled.template[0].containers
# }

# output "service_volumes_logging_disabled" {
#   description = "List of volumes in the Cloud Run service."
#   value = module.logging_disabled.template[0].volumes
# }

# output "ignored_volume_mounts_logging_disabled" {
#   description = "List of container volume_mounts that share name or mount_path with the Datadog shared volume and are not added to the Cloud Run service when logging is enabled."
#   value = module.logging_disabled.ignored_volume_mounts
# }

# output "ignored_containers_logging_disabled" {
#   description = "List of containers that are ignored by the module."
#   value = module.logging_disabled.ignored_containers
# }

# output "ignored_volumes_logging_disabled" {
#   description = "List of volumes that are ignored by the module."
#   value = module.logging_disabled.ignored_volumes
# }

output "module_level_override-cloud_run_service_name" {
  description = "Name of the Cloud Run service found on Datadog Serverless Monitoring."
  value = module.module-level-override.name
}

output "module_level_override-service_containers" {
  description = "List of containers in the Cloud Run service."
  value = module.module-level-override.template[0].containers
}

output "module_name_default-cloud_run_service_name" {
  description = "Name of the Cloud Run service found on Datadog Serverless Monitoring."
  value = module.module-name-default.name
}

output "module_name_default-service_containers" {
  description = "List of containers in the Cloud Run service."
  value = module.module-name-default.template[0].containers
}


output "container_level_override-cloud_run_service_name" {
  description = "Name of the Cloud Run service found on Datadog Serverless Monitoring."
  value = module.container-level-override.name
}

output "container_level_override-service_containers" {
  description = "List of containers in the Cloud Run service."
  value = module.container-level-override.template[0].containers
}
