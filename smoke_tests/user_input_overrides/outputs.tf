output "cloud_run_service_name_module_level_override" {
  description = "Name of the Cloud Run service found on Datadog Serverless Monitoring."
  value = module.module-level-override.name
}

output "service_containers_module_level_override" {
  description = "List of containers in the Cloud Run service."
  value = module.module-level-override.template[0].containers
}

output "service_volumes_module_level_override" {
  description = "List of volumes in the Cloud Run service."
  value = module.module-level-override.template[0].volumes
}

output "ignored_volume_mounts_module_level_override" {
  description = "List of container volume_mounts that share name or mount_path with the Datadog shared volume and are not added to the Cloud Run service when logging is enabled."
  value = module.module-level-override.ignored_volume_mounts
}

output "ignored_containers_module_level_override" {
  description = "List of containers that are ignored by the module."
  value = module.module-level-override.ignored_containers
}

output "ignored_volumes_module_level_override" {
  description = "List of volumes that are ignored by the module."
  value = module.module-level-override.ignored_volumes
}

output "cloud_run_service_name_module_name_default" {
  description = "Name of the Cloud Run service found on Datadog Serverless Monitoring."
  value = module.module-name-default.name
}

output "service_containers_module_name_default" {
  description = "List of containers in the Cloud Run service."
  value = module.module-name-default.template[0].containers
}

output "service_volumes_module_name_default" {
  description = "List of volumes in the Cloud Run service."
  value = module.module-name-default.template[0].volumes
}

output "ignored_volume_mounts_module_name_default" {
  description = "List of container volume_mounts that share name or mount_path with the Datadog shared volume and are not added to the Cloud Run service when logging is enabled."
  value = module.module-name-default.ignored_volume_mounts
}

output "ignored_containers_module_name_default" {
  description = "List of containers that are ignored by the module."
  value = module.module-name-default.ignored_containers
}

output "ignored_volumes_module_name_default" {
  description = "List of volumes that are ignored by the module."
  value = module.module-name-default.ignored_volumes
}

output "cloud_run_service_name_container_level_override" {
  description = "Name of the Cloud Run service found on Datadog Serverless Monitoring."
  value = module.container-level-override.name
}

output "service_containers_container_level_override" {
  description = "List of containers in the Cloud Run service."
  value = module.container-level-override.template[0].containers
}

output "service_volumes_container_level_override" {
  description = "List of volumes in the Cloud Run service."
  value = module.container-level-override.template[0].volumes
}

output "ignored_volume_mounts_container_level_override" {
  description = "List of container volume_mounts that share name or mount_path with the Datadog shared volume and are not added to the Cloud Run service when logging is enabled."
  value = module.container-level-override.ignored_volume_mounts
}

output "ignored_containers_container_level_override" {
  description = "List of containers that are ignored by the module."
  value = module.container-level-override.ignored_containers
}

output "ignored_volumes_container_level_override" {
  description = "List of volumes that are ignored by the module."
  value = module.container-level-override.ignored_volumes
}

