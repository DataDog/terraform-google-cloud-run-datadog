# Datadog Terraform module for Google Cloud Run

Use this Terraform module to install Datadog Serverless Monitoring for Google Cloud Run services.

This Terraform module wraps the [google_cloud_run_v2_resource](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/cloud_run_v2_service) and automatically configures your Cloud Run application for Datadog Serverless Monitoring by:

* creating the `google_cloud_run_v2_service` resource invocation
* adding the designated volumes, volume_mounts to the main container if the user enables logging
* adding the Datadog agent as a sidecar container to collect metrics, traces, and logs
* configuring environment variables for Datadog instrumentation

## Usage

The module syntax is the same regardless of runtime because language is isolated in its image container link.

```
module "datadog-cloud-run-v2-<language>" {
  source = "../../"
  name = var.name
  location = var.region
  deletion_protection = false

  datadog_api_key = "example-datadog-api-key"
  datadog_site = "datadoghq.com"
  datadog_service = "cloud-run-tf-<language>-example"
  datadog_version = "1.0.0"
  datadog_tags = ["test:tag-example", "foo:tag-example-2"]
  datadog_env = "serverless"
  datadog_enable_logging = true
  datadog_enable_tracing = true
  datadog_log_level = "debug"
  datadog_logging_path = "/shared-volume/logs/*.log"
  datadog_shared_volume = {
    name = "dd-shared-volume"
    mount_path = "/shared-volume"
  }


  datadog_sidecar = {
    #uses default sidecar image, name, resources, healthport
    image = "gcr.io/datadoghq/serverless-init:latest"
    name = "datadog-sidecar"
    
    resources = {
      limits = {
        cpu = "1"
        memory = "512Mi"
      }
    }
    health_port = 5555
  }

  template = {
    containers = [
      {
        name = "cloudrun-tf-<language>-example"
        image = "language-specific-app-container-image-link"
        resources = {
          limits = {
            cpu    = "1"
            memory = "512Mi"
          }
        }
        ports = {
          container_port = 8080
        }
      },
    ]
  }

}

## Configuration

### Module syntax
#### Wraps google_cloud_run_v2_service resource
- Arguments available in the [google_cloud_run_v2_service](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/cloud_run_v2_service#argument-reference) resource are available in this Terraform module.
- All blocks (template, containers, volumes, etc) in the resource are represented in the module as objects with required types - insert an "=" 
- Any optional blocks with 0-many occurrences are represented as a list-collection of objects with the same types/parameters as the blocks
- See [variables.tf](variables.tf) for the complete list of variables, or the table below for full syntax details/examples

#### Datadog Variables

The following Datadog variables should be set on application containers:

| Variable                 | Purpose                                                                                                                                 | How to Set                                                                                         |
| ------------------------ | --------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------- |
| `DD_SERVICE`             | Enables [Unified Service Tagging](https://docs.datadoghq.com/tagging/unified_service_tagging/). Defaults to the Cloud Run service name. | Set via the `datadog_service` parameter or per container in `template.containers[*].env`.              |
| `DD_SERVERLESS_LOG_PATH` | Used when logging is enabled (`datadog_enable_logging = true`). Is the path where logs are written and where the agent sidecar reads from.                         | Set via `datadog_logging_path`.                                                                    |
| `DD_LOGS_INJECTION`      | Enables automatic correlation of logs and traces.                                                                                       | Set automatically if `datadog_enable_logging = true`, or manually in `template.containers[*].env`. |
| `DD_TRACE_ENABLED`       | Toggles APM tracing. Defaults to `true`.                                                                                                | Leave unset to use the default, or override in `template.containers[*].env`.                       |


The following Datadog variables can be set for sidecar:

| Variable                          | Purpose                                                                               | How to Set                                                                         |
| --------------------------------- | ------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------- |
| `DD_SERVERLESS_LOG_PATH`          | Must match where the application containers write logs if logging is enabled.         | Automatically set via `datadog_logging_path` when `datadog_enable_logging = true`. |
| `DD_SERVICE`                      | Used for Unified Service Tagging. Defaults to the Cloud Run service name.             | Set via `datadog_service`.                                                         |
| `DD_VERSION`                      | (Optional) Part of Unified Service Tagging (e.g., Git SHA or application version).    | Set via `datadog_version`.                                                         |
| `DD_ENV`                          | (Optional) Part of Unified Service Tagging (e.g., `serverless`, `staging`).                 | Set via `datadog_env`.                                                             |
| `DD_SITE`                         | Target Datadog site (e.g., `datadoghq.com`, `datadoghq.eu`).                          | Set via `datadog_site`.                                                            |
| `DD_API_KEY`                      | API key used by the Datadog agent to send telemetry.                                  | Set via `datadog_api_key`.                                                         |
| `DD_HEALTH_PORT`                  | Port used by the sidecar’s startup probe. Defaults to `5555`.                         | Set via `datadog_sidecar.health_port`.                                             |
| `DD_LOG_LEVEL`                    | (Optional) Controls log verbosity in Cloud Run logs (`TRACE`, `DEBUG`, `INFO`, etc.). | Set via `datadog_log_level`.                                                       |
| Other agent environment variables | For advanced agent configuration. Avoid overriding any of the above variables.        | Set via `datadog_sidecar.env_vars`.                                                     |



#### Transitioning from resource to module
- 
- To avoid Terraform destroying the resource