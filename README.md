# Datadog Terraform module for Google Cloud Run

Use this Terraform module to install Datadog Serverless Monitoring for Google Cloud Run services.

This Terraform module wraps the [google_cloud_run_v2_resource](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/cloud_run_v2_service) and automatically configures your Cloud Run application for Datadog Serverless Monitoring by:

* creating the `google_cloud_run_v2_service` resource invocation
* adding the designated volumes, volume_mounts to the main container if the user enables logging
* enabling the Datadog agent as a sidecar container to collect metrics, traces, and logs