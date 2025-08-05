output "cloud_run_service_name" {
  description = "Name of the Cloud Run service found on Datadog Serverless Monitoring."
  value = module.datadog-cloud-run-v2-wrapper.name
}


