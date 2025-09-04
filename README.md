# Datadog Terraform module for Google Cloud Run

Use this Terraform module to install Datadog Serverless Monitoring for Google Cloud Run services.

This Terraform module wraps the [google_cloud_run_v2_resource](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/cloud_run_v2_service) and automatically configures your Cloud Run application for Datadog Serverless Monitoring by:

* creating the `google_cloud_run_v2_service` resource invocation
* adding the designated volumes, volume_mounts to the main container if the user enables logging
* adding the Datadog agent as a sidecar container to collect metrics, traces, and logs
* configuring environment variables for Datadog instrumentation

## Usage


```
module "datadog-cloud-run-v2-<language>" {
  source = "DataDog/cloud-run-datadog/google"
  name = var.name
  location = var.region
  deletion_protection = false

  datadog_api_key = "example-datadog-api-key"
  datadog_service = "cloud-run-tf-<language>-example"
  datadog_version = "1.0.0"
  datadog_env = "serverless"
  datadog_enable_logging = true


  datadog_sidecar = {
    # use default sidecar image, name, resources, healthport
  }

  template = {
    containers = [
      {
        name = "my-cloud-run-app"
        image = "us-docker.pkg.dev/cloudrun/container/hello"
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
```

**Note:** Make sure exactly one of the containers passed into `template.containers` has a `ports` block:
```
ports = {
    container_port = <Port number>
}
```


## Configuration

### Module syntax
#### Wraps google_cloud_run_v2_service resource
- Arguments available in the [google_cloud_run_v2_service](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/cloud_run_v2_service#argument-reference) resource are available in this Terraform module.
- All blocks (template, containers, volumes, etc) in the resource are represented in the module as objects with required types - insert an `=`
- Any resource optional blocks that can occur multiple times are represented as a list-collection of objects with the same types/parameters as the blocks
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

If you've an established resource instrumentation but would like to switch to the module instead:
- Add an `=` to *every* resources block, and for optional, repeatable blocks like `volumes`, `volume_mounts`, `env`, `containers` convert them to a list of objects representation
- Make sure to remove any containers with the datadog sidecar name from your `template`, and remove any DD_* environment variables from your app containers
- Declare the DD_* environment variables either in the corresponding module's `datadog_*` parameters or as container env vars in `template.containers[*].env`
- To avoid Terraform destroying the resource, declare a `moved` block in your configuration, making sure the `name` parameter in both module and resource are the same so the service is updated in place:

```tf
   moved {
    from = google_cloud_run_v2_service.{your_service}
    to   = module.{your_service}.google_cloud_run_v2_service.this
   }
```

##### google_cloud_run_v2_service resource
```
resource "google_cloud_run_v2_service" "example_cloud_run_service" {
  name = "cloud-run-example"
  ...
  template {
    containers {
        name = "main-container"
        image = "us-docker.pkg.dev/cloudrun/container/hello"
    }
    containers {
        name = "container-2"
        image = "us-docker.pkg.dev/cloudrun/container/hello:latest"
    }
  }
  ...
}

```

##### Datadog Terraform module for Google Cloud Run
```
module "example_cloud_run_service" {
  source = "Datadog/cloud-run-datadog/google" <TODO: once published!>
  name = "cloud-run-example"
  ...
  template = {
    containers = [
      {
        name = "main-container"
        image = "us-docker.pkg.dev/cloudrun/container/hello"
      },
      {
        name = "container-2"
        image = "us-docker.pkg.dev/cloudrun/container/hello:latest"
      },
    ]
  }
  ...
}
```


<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.5.0 |
| <a name="requirement_google"></a> [google](#requirement\_google) | >= 7.1.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [google_cloud_run_v2_service.this](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/cloud_run_v2_service) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_annotations"></a> [annotations](#input\_annotations) | Unstructured key value map that may be set by external tools to store and arbitrary metadata. They are not queryable and should be preserved when modifying objects.<br/><br/>Cloud Run API v2 does not support annotations with 'run.googleapis.com', 'cloud.googleapis.com', 'serving.knative.dev', or 'autoscaling.knative.dev' namespaces, and they will be rejected in new resources.<br/>All system annotations in v1 now have a corresponding field in v2 Service.<br/><br/>This field follows Kubernetes annotations' namespacing, limits, and rules.<br/><br/>**Note**: This field is non-authoritative, and will only manage the annotations present in your configuration.<br/>Please refer to the field 'effective\_annotations' for all of the annotations present on the resource. | `map(string)` | `null` | no |
| <a name="input_binary_authorization"></a> [binary\_authorization](#input\_binary\_authorization) | n/a | <pre>object({<br/>    breakglass_justification = optional(string),<br/>    policy                   = optional(string),<br/>    use_default              = optional(bool)<br/>  })</pre> | `null` | no |
| <a name="input_build_config"></a> [build\_config](#input\_build\_config) | n/a | <pre>object({<br/>    base_image               = optional(string),<br/>    enable_automatic_updates = optional(bool),<br/>    environment_variables    = optional(map(string)),<br/>    function_target          = optional(string),<br/>    image_uri                = optional(string),<br/>    service_account          = optional(string),<br/>    source_location          = optional(string),<br/>    worker_pool              = optional(string)<br/>  })</pre> | `null` | no |
| <a name="input_client"></a> [client](#input\_client) | Arbitrary identifier for the API client. | `string` | `null` | no |
| <a name="input_client_version"></a> [client\_version](#input\_client\_version) | Arbitrary version identifier for the API client. | `string` | `null` | no |
| <a name="input_custom_audiences"></a> [custom\_audiences](#input\_custom\_audiences) | One or more custom audiences that you want this service to support. Specify each custom audience as the full URL in a string. The custom audiences are encoded in the token and used to authenticate requests.<br/>For more information, see https://cloud.google.com/run/docs/configuring/custom-audiences. | `list(string)` | `null` | no |
| <a name="input_datadog_api_key"></a> [datadog\_api\_key](#input\_datadog\_api\_key) | Datadog API key | `string` | n/a | yes |
| <a name="input_datadog_enable_logging"></a> [datadog\_enable\_logging](#input\_datadog\_enable\_logging) | Enables log collection. Defaults to true. | `bool` | `true` | no |
| <a name="input_datadog_env"></a> [datadog\_env](#input\_datadog\_env) | Datadog Environment tag, used for Unified Service Tagging. | `string` | `null` | no |
| <a name="input_datadog_log_level"></a> [datadog\_log\_level](#input\_datadog\_log\_level) | Datadog agent's level of log output in Cloud Run UI, from most to least output: TRACE, DEBUG, INFO, WARN, ERROR, CRITICAL | `string` | `null` | no |
| <a name="input_datadog_logging_path"></a> [datadog\_logging\_path](#input\_datadog\_logging\_path) | Datadog logging path to be used for log collection. Ensure var.datadog\_enable\_logging is true. Must begin with path given in var.datadog\_shared\_volume.mount\_path. | `string` | `"/shared-volume/logs/*.log"` | no |
| <a name="input_datadog_service"></a> [datadog\_service](#input\_datadog\_service) | Datadog Service tag, used for Unified Service Tagging. | `string` | `null` | no |
| <a name="input_datadog_shared_volume"></a> [datadog\_shared\_volume](#input\_datadog\_shared\_volume) | Datadog shared volume for log collection. Ensure var.datadog\_enable\_logging is true. Note: will always be of type empty\_dir and in-memory. If a volume with this name is provided as part of var.template.volumes, it will be overridden. | <pre>object({<br/>    name       = string<br/>    mount_path = string<br/>    size_limit = optional(string)<br/>  })</pre> | <pre>{<br/>  "mount_path": "/shared-volume",<br/>  "name": "shared-volume"<br/>}</pre> | no |
| <a name="input_datadog_sidecar"></a> [datadog\_sidecar](#input\_datadog\_sidecar) | Datadog sidecar configuration. Nested attributes include:<br/>- image - Image for version of Datadog agent to use.<br/>- name - Name of the sidecar container.<br/>- resources - Resources like for any cloud run container.<br/>- startup\_probe - Startup probe settings only for failure\_threshold, initial\_delay\_seconds, period\_seconds, timeout\_seconds.<br/>- health\_port - Health port to start the startup probe.<br/>- env\_vars - List of environment variables with name and value fieldsfor customizing Datadog agent configuration, if any. | <pre>object({<br/>    image = optional(string, "gcr.io/datadoghq/serverless-init:latest")<br/>    name  = optional(string, "datadog-sidecar")<br/>    resources = optional(object({<br/>      limits = optional(object({<br/>        cpu    = optional(string, "1")<br/>        memory = optional(string, "512Mi")<br/>      }), null),<br/>      }), { # default sidecar resources<br/>      limits = {<br/>        cpu    = "1"<br/>        memory = "512Mi"<br/>      }<br/>    })<br/>    startup_probe = optional(<br/>      object({<br/>        failure_threshold     = optional(number),<br/>        initial_delay_seconds = optional(number),<br/>        period_seconds        = optional(number),<br/>        timeout_seconds       = optional(number),<br/>      }),<br/>      { # default startup probe<br/>        failure_threshold     = 3<br/>        period_seconds        = 10<br/>        initial_delay_seconds = 0<br/>        timeout_seconds       = 1<br/>      }<br/>    )<br/>    health_port = optional(number, 5555) # DD_HEALTH_PORT<br/>    env = optional(list(object({         # user-customizable env vars for Datadog agent configuration<br/>      name  = string<br/>      value = string<br/>    })), null)<br/>  })</pre> | <pre>{<br/>  "health_port": 5555,<br/>  "image": "gcr.io/datadoghq/serverless-init:latest",<br/>  "name": "datadog-sidecar",<br/>  "resources": {<br/>    "limits": {<br/>      "cpu": "1",<br/>      "memory": "512Mi"<br/>    }<br/>  },<br/>  "startup_probe": {<br/>    "failure_threshold": 3,<br/>    "initial_delay_seconds": 0,<br/>    "period_seconds": 10,<br/>    "timeout_seconds": 1<br/>  }<br/>}</pre> | no |
| <a name="input_datadog_site"></a> [datadog\_site](#input\_datadog\_site) | Datadog site | `string` | `"datadoghq.com"` | no |
| <a name="input_datadog_tags"></a> [datadog\_tags](#input\_datadog\_tags) | Datadog tags | `list(string)` | `null` | no |
| <a name="input_datadog_version"></a> [datadog\_version](#input\_datadog\_version) | Datadog Version tag, used for Unified Service Tagging. | `string` | `null` | no |
| <a name="input_deletion_protection"></a> [deletion\_protection](#input\_deletion\_protection) | Whether Terraform will be prevented from destroying the service. Defaults to true.<br/>When a'terraform destroy' or 'terraform apply' would delete the service,<br/>the command will fail if this field is not set to false in Terraform state.<br/>When the field is set to true or unset in Terraform state, a 'terraform apply'<br/>or 'terraform destroy' that would delete the service will fail.<br/>When the field is set to false, deleting the service is allowed. | `bool` | `null` | no |
| <a name="input_description"></a> [description](#input\_description) | User-provided description of the Service. This field currently has a 512-character limit. | `string` | `null` | no |
| <a name="input_ingress"></a> [ingress](#input\_ingress) | Provides the ingress settings for this Service. On output, returns the currently observed ingress settings, or INGRESS\_TRAFFIC\_UNSPECIFIED if no revision is active. Possible values: ["INGRESS\_TRAFFIC\_ALL", "INGRESS\_TRAFFIC\_INTERNAL\_ONLY", "INGRESS\_TRAFFIC\_INTERNAL\_LOAD\_BALANCER"] | `string` | `null` | no |
| <a name="input_invoker_iam_disabled"></a> [invoker\_iam\_disabled](#input\_invoker\_iam\_disabled) | Disables IAM permission check for run.routes.invoke for callers of this service. For more information, visit https://cloud.google.com/run/docs/securing/managing-access#invoker_check. | `bool` | `null` | no |
| <a name="input_labels"></a> [labels](#input\_labels) | Unstructured key value map that can be used to organize and categorize objects. User-provided labels are shared with Google's billing system, so they can be used to filter, or break down billing charges by team, component,<br/>environment, state, etc. For more information, visit https://cloud.google.com/resource-manager/docs/creating-managing-labels or https://cloud.google.com/run/docs/configuring/labels.<br/><br/>Cloud Run API v2 does not support labels with  'run.googleapis.com', 'cloud.googleapis.com', 'serving.knative.dev', or 'autoscaling.knative.dev' namespaces, and they will be rejected.<br/>All system labels in v1 now have a corresponding field in v2 Service.<br/><br/>**Note**: This field is non-authoritative, and will only manage the labels present in your configuration.<br/>Please refer to the field 'effective\_labels' for all of the labels present on the resource. | `map(string)` | `null` | no |
| <a name="input_launch_stage"></a> [launch\_stage](#input\_launch\_stage) | The launch stage as defined by [Google Cloud Platform Launch Stages](https://cloud.google.com/products#product-launch-stages). Cloud Run supports ALPHA, BETA, and GA.<br/>If no value is specified, GA is assumed. Set the launch stage to a preview stage on input to allow use of preview features in that stage. On read (or output), describes whether the resource uses preview features.<br/><br/>For example, if ALPHA is provided as input, but only BETA and GA-level features are used, this field will be BETA on output. Possible values: ["UNIMPLEMENTED", "PRELAUNCH", "EARLY\_ACCESS", "ALPHA", "BETA", "GA", "DEPRECATED"] | `string` | `null` | no |
| <a name="input_location"></a> [location](#input\_location) | The location of the cloud run service | `string` | n/a | yes |
| <a name="input_multi_region_settings"></a> [multi\_region\_settings](#input\_multi\_region\_settings) | n/a | <pre>object({<br/>    regions = optional(list(string))<br/>  })</pre> | `null` | no |
| <a name="input_name"></a> [name](#input\_name) | Name of the Service. | `string` | n/a | yes |
| <a name="input_project"></a> [project](#input\_project) | n/a | `string` | `null` | no |
| <a name="input_scaling"></a> [scaling](#input\_scaling) | n/a | <pre>object({<br/>    manual_instance_count = optional(number),<br/>    max_instance_count    = optional(number),<br/>    min_instance_count    = optional(number),<br/>    scaling_mode          = optional(string)<br/>  })</pre> | `null` | no |
| <a name="input_template"></a> [template](#input\_template) | n/a | <pre>object({<br/>    annotations                      = optional(map(string)),<br/>    encryption_key                   = optional(string),<br/>    execution_environment            = optional(string),<br/>    gpu_zonal_redundancy_disabled    = optional(bool),<br/>    labels                           = optional(map(string)),<br/>    max_instance_request_concurrency = optional(number),<br/>    revision                         = optional(string),<br/>    service_account                  = optional(string),<br/>    session_affinity                 = optional(bool),<br/>    timeout                          = optional(string),<br/>    containers = optional(list(object({<br/>      args           = optional(list(string)),<br/>      base_image_uri = optional(string),<br/>      command        = optional(list(string)),<br/>      depends_on     = optional(list(string)),<br/>      image          = string,<br/>      name           = optional(string),<br/>      working_dir    = optional(string),<br/>      env = optional(set(object({<br/>        name  = string,<br/>        value = optional(string),<br/>        value_source = optional(object({<br/>          secret_key_ref = optional(object({<br/>            secret  = string,<br/>            version = optional(string)<br/>          }))<br/>        }))<br/>      }))),<br/>      liveness_probe = optional(object({<br/>        failure_threshold     = optional(number),<br/>        initial_delay_seconds = optional(number),<br/>        period_seconds        = optional(number),<br/>        timeout_seconds       = optional(number),<br/>        grpc = optional(object({<br/>          port    = optional(number),<br/>          service = optional(string)<br/>        })),<br/>        http_get = optional(object({<br/>          path = optional(string),<br/>          port = optional(number),<br/>          http_headers = optional(list(object({<br/>            name  = string,<br/>            value = optional(string)<br/>          })))<br/>        })),<br/>        tcp_socket = optional(object({<br/>          port = number<br/>        }))<br/>      })),<br/>      ports = optional(object({<br/>        container_port = optional(number),<br/>        name           = optional(string)<br/>      })),<br/>      resources = optional(object({<br/>        cpu_idle          = optional(bool),<br/>        limits            = optional(map(string)),<br/>        startup_cpu_boost = optional(bool)<br/>      })),<br/>      startup_probe = optional(object({<br/>        failure_threshold     = optional(number),<br/>        initial_delay_seconds = optional(number),<br/>        period_seconds        = optional(number),<br/>        timeout_seconds       = optional(number),<br/>        grpc = optional(object({<br/>          port    = optional(number),<br/>          service = optional(string)<br/>        })),<br/>        http_get = optional(object({<br/>          path = optional(string),<br/>          port = optional(number),<br/>          http_headers = optional(list(object({<br/>            name  = string,<br/>            value = optional(string)<br/>          })))<br/>        })),<br/>        tcp_socket = optional(object({<br/>          port = optional(number)<br/>        }))<br/>      })),<br/>      volume_mounts = optional(list(object({<br/>        mount_path = string,<br/>        name       = string<br/>      })))<br/>    }))),<br/>    node_selector = optional(object({<br/>      accelerator = string<br/>    })),<br/>    scaling = optional(object({<br/>      max_instance_count = optional(number),<br/>      min_instance_count = optional(number)<br/>    })),<br/>    volumes = optional(list(object({<br/>      name = string,<br/>      cloud_sql_instance = optional(object({<br/>        instances = optional(set(string))<br/>      })),<br/>      empty_dir = optional(object({<br/>        medium     = optional(string),<br/>        size_limit = optional(string)<br/>      })),<br/>      gcs = optional(object({<br/>        bucket    = string,<br/>        read_only = optional(bool)<br/>      })),<br/>      nfs = optional(object({<br/>        path      = string,<br/>        read_only = optional(bool),<br/>        server    = string<br/>      })),<br/>      secret = optional(object({<br/>        default_mode = optional(number),<br/>        secret       = string,<br/>        items = optional(list(object({<br/>          mode    = optional(number),<br/>          path    = string,<br/>          version = optional(string)<br/>        })))<br/>      }))<br/>    }))),<br/>    vpc_access = optional(object({<br/>      connector = optional(string),<br/>      egress    = optional(string),<br/>      network_interfaces = optional(list(object({<br/>        network    = optional(string),<br/>        subnetwork = optional(string),<br/>        tags       = optional(list(string))<br/>      })))<br/>    }))<br/>  })</pre> | n/a | yes |
| <a name="input_timeouts"></a> [timeouts](#input\_timeouts) | n/a | <pre>object({<br/>    create = optional(string),<br/>    delete = optional(string),<br/>    update = optional(string)<br/>  })</pre> | `null` | no |
| <a name="input_traffic"></a> [traffic](#input\_traffic) | n/a | <pre>list(object({<br/>    percent  = optional(number),<br/>    revision = optional(string),<br/>    tag      = optional(string),<br/>    type     = optional(string)<br/>  }))</pre> | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_annotations"></a> [annotations](#output\_annotations) | Unstructured key value map that may be set by external tools to store and arbitrary metadata. They are not queryable and should be preserved when modifying objects.<br/><br/>Cloud Run API v2 does not support annotations with 'run.googleapis.com', 'cloud.googleapis.com', 'serving.knative.dev', or 'autoscaling.knative.dev' namespaces, and they will be rejected in new resources.<br/>All system annotations in v1 now have a corresponding field in v2 Service.<br/><br/>This field follows Kubernetes annotations' namespacing, limits, and rules.<br/><br/>**Note**: This field is non-authoritative, and will only manage the annotations present in your configuration.<br/>Please refer to the field 'effective\_annotations' for all of the annotations present on the resource. |
| <a name="output_binary_authorization"></a> [binary\_authorization](#output\_binary\_authorization) | n/a |
| <a name="output_build_config"></a> [build\_config](#output\_build\_config) | n/a |
| <a name="output_client"></a> [client](#output\_client) | Arbitrary identifier for the API client. |
| <a name="output_client_version"></a> [client\_version](#output\_client\_version) | Arbitrary version identifier for the API client. |
| <a name="output_conditions"></a> [conditions](#output\_conditions) | The Conditions of all other associated sub-resources. They contain additional diagnostics information in case the Service does not reach its Serving state. See comments in reconciling for additional information on reconciliation process in Cloud Run. |
| <a name="output_create_time"></a> [create\_time](#output\_create\_time) | The creation time. |
| <a name="output_creator"></a> [creator](#output\_creator) | Email address of the authenticated creator. |
| <a name="output_custom_audiences"></a> [custom\_audiences](#output\_custom\_audiences) | One or more custom audiences that you want this service to support. Specify each custom audience as the full URL in a string. The custom audiences are encoded in the token and used to authenticate requests.<br/>For more information, see https://cloud.google.com/run/docs/configuring/custom-audiences. |
| <a name="output_delete_time"></a> [delete\_time](#output\_delete\_time) | The deletion time. |
| <a name="output_deletion_protection"></a> [deletion\_protection](#output\_deletion\_protection) | Whether Terraform will be prevented from destroying the service. Defaults to true.<br/>When a'terraform destroy' or 'terraform apply' would delete the service,<br/>the command will fail if this field is not set to false in Terraform state.<br/>When the field is set to true or unset in Terraform state, a 'terraform apply'<br/>or 'terraform destroy' that would delete the service will fail.<br/>When the field is set to false, deleting the service is allowed. |
| <a name="output_description"></a> [description](#output\_description) | User-provided description of the Service. This field currently has a 512-character limit. |
| <a name="output_effective_annotations"></a> [effective\_annotations](#output\_effective\_annotations) | All of annotations (key/value pairs) present on the resource in GCP, including the annotations configured through Terraform, other clients and services. |
| <a name="output_effective_labels"></a> [effective\_labels](#output\_effective\_labels) | All of labels (key/value pairs) present on the resource in GCP, including the labels configured through Terraform, other clients and services. |
| <a name="output_etag"></a> [etag](#output\_etag) | A system-generated fingerprint for this version of the resource. May be used to detect modification conflict during updates. |
| <a name="output_expire_time"></a> [expire\_time](#output\_expire\_time) | For a deleted resource, the time after which it will be permanently deleted. |
| <a name="output_generation"></a> [generation](#output\_generation) | A number that monotonically increases every time the user modifies the desired state. Please note that unlike v1, this is an int64 value. As with most Google APIs, its JSON representation will be a string instead of an integer. |
| <a name="output_id"></a> [id](#output\_id) | n/a |
| <a name="output_ignored_containers"></a> [ignored\_containers](#output\_ignored\_containers) | List of containers that are ignored by the module. |
| <a name="output_ignored_volume_mounts"></a> [ignored\_volume\_mounts](#output\_ignored\_volume\_mounts) | List of volume mounts that overlap with the Datadog shared volume and are ignored by the module. |
| <a name="output_ignored_volumes"></a> [ignored\_volumes](#output\_ignored\_volumes) | List of volumes that are ignored by the module. |
| <a name="output_ingress"></a> [ingress](#output\_ingress) | Provides the ingress settings for this Service. On output, returns the currently observed ingress settings, or INGRESS\_TRAFFIC\_UNSPECIFIED if no revision is active. Possible values: ["INGRESS\_TRAFFIC\_ALL", "INGRESS\_TRAFFIC\_INTERNAL\_ONLY", "INGRESS\_TRAFFIC\_INTERNAL\_LOAD\_BALANCER"] |
| <a name="output_invoker_iam_disabled"></a> [invoker\_iam\_disabled](#output\_invoker\_iam\_disabled) | Disables IAM permission check for run.routes.invoke for callers of this service. For more information, visit https://cloud.google.com/run/docs/securing/managing-access#invoker_check. |
| <a name="output_labels"></a> [labels](#output\_labels) | Unstructured key value map that can be used to organize and categorize objects. User-provided labels are shared with Google's billing system, so they can be used to filter, or break down billing charges by team, component,<br/>environment, state, etc. For more information, visit https://cloud.google.com/resource-manager/docs/creating-managing-labels or https://cloud.google.com/run/docs/configuring/labels.<br/><br/>Cloud Run API v2 does not support labels with  'run.googleapis.com', 'cloud.googleapis.com', 'serving.knative.dev', or 'autoscaling.knative.dev' namespaces, and they will be rejected.<br/>All system labels in v1 now have a corresponding field in v2 Service.<br/><br/>**Note**: This field is non-authoritative, and will only manage the labels present in your configuration.<br/>Please refer to the field 'effective\_labels' for all of the labels present on the resource. |
| <a name="output_last_modifier"></a> [last\_modifier](#output\_last\_modifier) | Email address of the last authenticated modifier. |
| <a name="output_latest_created_revision"></a> [latest\_created\_revision](#output\_latest\_created\_revision) | Name of the last created revision. See comments in reconciling for additional information on reconciliation process in Cloud Run. |
| <a name="output_latest_ready_revision"></a> [latest\_ready\_revision](#output\_latest\_ready\_revision) | Name of the latest revision that is serving traffic. See comments in reconciling for additional information on reconciliation process in Cloud Run. |
| <a name="output_launch_stage"></a> [launch\_stage](#output\_launch\_stage) | The launch stage as defined by [Google Cloud Platform Launch Stages](https://cloud.google.com/products#product-launch-stages). Cloud Run supports ALPHA, BETA, and GA.<br/>If no value is specified, GA is assumed. Set the launch stage to a preview stage on input to allow use of preview features in that stage. On read (or output), describes whether the resource uses preview features.<br/><br/>For example, if ALPHA is provided as input, but only BETA and GA-level features are used, this field will be BETA on output. Possible values: ["UNIMPLEMENTED", "PRELAUNCH", "EARLY\_ACCESS", "ALPHA", "BETA", "GA", "DEPRECATED"] |
| <a name="output_location"></a> [location](#output\_location) | The location of the cloud run service |
| <a name="output_multi_region_settings"></a> [multi\_region\_settings](#output\_multi\_region\_settings) | n/a |
| <a name="output_name"></a> [name](#output\_name) | Name of the Service. |
| <a name="output_observed_generation"></a> [observed\_generation](#output\_observed\_generation) | The generation of this Service currently serving traffic. See comments in reconciling for additional information on reconciliation process in Cloud Run. Please note that unlike v1, this is an int64 value. As with most Google APIs, its JSON representation will be a string instead of an integer. |
| <a name="output_project"></a> [project](#output\_project) | n/a |
| <a name="output_reconciling"></a> [reconciling](#output\_reconciling) | Returns true if the Service is currently being acted upon by the system to bring it into the desired state.<br/><br/>When a new Service is created, or an existing one is updated, Cloud Run will asynchronously perform all necessary steps to bring the Service to the desired serving state. This process is called reconciliation. While reconciliation is in process, observedGeneration, latest\_ready\_revison, trafficStatuses, and uri will have transient values that might mismatch the intended state: Once reconciliation is over (and this field is false), there are two possible outcomes: reconciliation succeeded and the serving state matches the Service, or there was an error, and reconciliation failed. This state can be found in terminalCondition.state.<br/><br/>If reconciliation succeeded, the following fields will match: traffic and trafficStatuses, observedGeneration and generation, latestReadyRevision and latestCreatedRevision.<br/><br/>If reconciliation failed, trafficStatuses, observedGeneration, and latestReadyRevision will have the state of the last serving revision, or empty for newly created Services. Additional information on the failure can be found in terminalCondition and conditions. |
| <a name="output_scaling"></a> [scaling](#output\_scaling) | n/a |
| <a name="output_template"></a> [template](#output\_template) | n/a |
| <a name="output_terminal_condition"></a> [terminal\_condition](#output\_terminal\_condition) | The Condition of this Service, containing its readiness status, and detailed error information in case it did not reach a serving state. See comments in reconciling for additional information on reconciliation process in Cloud Run. |
| <a name="output_terraform_labels"></a> [terraform\_labels](#output\_terraform\_labels) | The combination of labels configured directly on the resource<br/> and default labels configured on the provider. |
| <a name="output_timeouts"></a> [timeouts](#output\_timeouts) | n/a |
| <a name="output_traffic"></a> [traffic](#output\_traffic) | n/a |
| <a name="output_traffic_statuses"></a> [traffic\_statuses](#output\_traffic\_statuses) | Detailed status information for corresponding traffic targets. See comments in reconciling for additional information on reconciliation process in Cloud Run. |
| <a name="output_uid"></a> [uid](#output\_uid) | Server assigned unique identifier for the trigger. The value is a UUID4 string and guaranteed to remain unchanged until the resource is deleted. |
| <a name="output_update_time"></a> [update\_time](#output\_update\_time) | The last-modified time. |
| <a name="output_uri"></a> [uri](#output\_uri) | The main URI in which this Service is serving traffic. |
| <a name="output_urls"></a> [urls](#output\_urls) | All URLs serving traffic for this Service. |
<!-- END_TF_DOCS -->
