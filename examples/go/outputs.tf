# Unless explicitly stated otherwise all files in this repository are licensed under the Apache-2.0 License.
# This product includes software developed at Datadog (https://www.datadoghq.com/) Copyright 2025 Datadog, Inc.

output "cloud_run_service_name" {
  description = "Name of the Cloud Run service found on Datadog Serverless Monitoring."
  value       = module.datadog-cloud-run-v2-go.name
}

output "service_containers" {
  description = "List of containers in the Cloud Run service."
  value       = module.datadog-cloud-run-v2-go.template[0].containers
}

output "service_volumes" {
  description = "List of volumes in the Cloud Run service."
  value       = module.datadog-cloud-run-v2-go.template[0].volumes
}

output "ignored_volume_mounts" {
  description = "List of container volume_mounts that share name or mount_path with the Datadog shared volume and are not added to the Cloud Run service when logging is enabled."
  value       = module.datadog-cloud-run-v2-go.ignored_volume_mounts
}

output "ignored_containers" {
  description = "List of containers that are ignored by the module."
  value       = module.datadog-cloud-run-v2-go.ignored_containers
}

output "ignored_volumes" {
  description = "List of volumes that are ignored by the module."
  value       = module.datadog-cloud-run-v2-go.ignored_volumes
}
