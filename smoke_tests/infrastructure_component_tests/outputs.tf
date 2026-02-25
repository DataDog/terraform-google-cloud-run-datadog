# Unless explicitly stated otherwise all files in this repository are licensed under the Apache-2.0 License.
# This product includes software developed at Datadog (https://www.datadoghq.com/) Copyright 2025 Datadog, Inc.

output "logging_enabled-cloud_run_service_name" {
  description = "Name of the Cloud Run service found on Datadog Serverless Monitoring."
  value       = module.logging_enabled.name
}

output "logging_enabled-service_containers" {
  description = "List of containers in the Cloud Run service."
  value       = module.logging_enabled.template[0].containers
}

output "logging_enabled_ignored_containers" {
  description = "List of containers that are ignored by the module."
  value       = module.logging_enabled.ignored_containers
}

output "logging_enabled_ignored_volumes" {
  description = "List of volumes that are ignored by the module."
  value       = module.logging_enabled.ignored_volumes
}

output "logging_enabled_ignored_volume_mounts" {
  description = "List of volume_mounts that are ignored by the module."
  value       = module.logging_enabled.ignored_volume_mounts
}

output "logging_disabled-cloud_run_service_name" {
  description = "Name of the Cloud Run service found on Datadog Serverless Monitoring."
  value       = module.logging_disabled.name
}

output "logging_disabled-service_containers" {
  description = "List of containers in the Cloud Run service."
  value       = module.logging_disabled.template[0].containers
}

output "logging_disabled_ignored_containers" {
  description = "List of containers that are ignored by the module."
  value       = module.logging_disabled.ignored_containers
}

output "logging_disabled_ignored_volumes" {
  description = "List of volumes that are ignored by the module."
  value       = module.logging_disabled.ignored_volumes
}

output "logging_disabled_ignored_volume_mounts" {
  description = "List of volume_mounts that are ignored by the module."
  value       = module.logging_disabled.ignored_volume_mounts
}

output "cloudsql_volume-service_containers" {
  description = "Containers for the Cloud SQL and shared volume test."
  value       = module.cloudsql-volume.template[0].containers
}

output "cloudsql_volume-service_volumes" {
  description = "Volumes for the Cloud SQL and shared volume test."
  value       = module.cloudsql-volume.template[0].volumes
}
