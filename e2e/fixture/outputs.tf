# Unless explicitly stated otherwise all files in this repository are licensed under the Apache-2.0 License.
# This product includes software developed at Datadog (https://www.datadoghq.com/) Copyright 2026 Datadog, Inc.

output "service_name" {
  description = "Name of the Cloud Run service created by the module."
  value       = module.datadog.name
}

output "service_uri" {
  description = "HTTPS URI the service serves traffic on; used as the trigger endpoint."
  value       = module.datadog.uri
}
