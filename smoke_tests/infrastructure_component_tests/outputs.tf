output "logging_enabled-cloud_run_service_name" {
  description = "Name of the Cloud Run service found on Datadog Serverless Monitoring."
  value = module.logging_enabled.name
}

output "logging_enabled-service_containers" {
  description = "List of containers in the Cloud Run service."
  value = module.logging_enabled.template[0].containers
} 

output "logging_enabled_ignored_containers" {
  description = "List of containers that are ignored by the module."
  value = module.logging_enabled.ignored_containers
}

output "logging_enabled_ignored_volumes" {
  description = "List of volumes that are ignored by the module."
  value = module.logging_enabled.ignored_volumes
}

output "logging_enabled_ignored_volume_mounts" {
  description = "List of volume_mounts that are ignored by the module."
  value = module.logging_enabled.ignored_volume_mounts
}

output "logging_disabled-cloud_run_service_name" {
  description = "Name of the Cloud Run service found on Datadog Serverless Monitoring."
  value = module.logging_disabled.name
}

output "logging_disabled-service_containers" {
  description = "List of containers in the Cloud Run service."
  value = module.logging_disabled.template[0].containers
} 

output "logging_disabled_ignored_containers" {
  description = "List of containers that are ignored by the module."
  value = module.logging_disabled.ignored_containers
}

output "logging_disabled_ignored_volumes" {
  description = "List of volumes that are ignored by the module."
  value = module.logging_disabled.ignored_volumes
}

output "logging_disabled_ignored_volume_mounts" {
  description = "List of volume_mounts that are ignored by the module."
  value = module.logging_disabled.ignored_volume_mounts
}