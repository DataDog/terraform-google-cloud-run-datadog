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


output "sidecar-user-env-vars-test-cloud_run_service_name" {
  description = "Name of the Cloud Run service found on Datadog Serverless Monitoring."
  value = module.sidecar-user-env-vars-test.name
}

output "sidecar-user-env-vars-test-service_containers" {
  description = "List of containers in the Cloud Run service."
  value = module.sidecar-user-env-vars-test.template[0].containers
} 
