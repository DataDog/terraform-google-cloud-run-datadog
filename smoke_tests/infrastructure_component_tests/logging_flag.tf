# Unless explicitly stated otherwise all files in this repository are licensed under the Apache-2.0 License.
# This product includes software developed at Datadog (https://www.datadoghq.com/) Copyright 2025 Datadog, Inc.

# ### Tests for the logging flag, correct architectures added and user-provided values overridden if logging is enabled, keep the user-provided values otherwise


provider "google" {
  project = var.project
  region  = var.region
}


## When logging is enabled:
# - The module should add the Datadog sidecar to the service (overriding the user-provided sidecar if applicable)
# - The module should add the Datadog shared volume to the service (ignores user-provided template.volumes with same name if applicable)
# - The module should add the Datadog volume_mounts to the service (ignores user-provided volume_mounts with same name or mount_path if applicable)
# - The module should add the Datadog logging path to the service (ignores user-designated DD_SERVERLESS_LOG_PATH in template.containers.env or datadog_sidecar.env_vars)
module "logging_enabled" {
  source = "../../"
  name = "cloudrun-test-overrides-when-logging-enabled-smoke1"
  location = var.region
  deletion_protection = false

  datadog_api_key = var.datadog_api_key
  datadog_site = "datadoghq.com"
  datadog_service = "cloudrun-tf-enabled-logging-structs"
  datadog_version = "1.0.0"
  datadog_tags = ["test:tag-example", "foo:tag-example-2"]
  datadog_env = "serverless"
  datadog_enable_logging = true
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
    env_vars = [
      {
        name = "DD_SERVERLESS_LOG_PATH"
        value = "path-should-not-be-used" # user-provided logging path should be ignored when logging is enabled
      }
    ]
    health_port = 5555
  }

  template = {
    labels = {
      "my_label" = "test_label"
    }
    volumes = [
      {
        name = "test-volume"
        empty_dir = {
          medium = "MEMORY"
          size_limit = "100Mi"
        }
      },
      {
        name = "dd-shared-volume" # not added by module if volume already exists in user-provided volumes list
        empty_dir = {
          medium = "MEMORY"
          size_limit = "100Mi"
        }
      },
      {
        name = "good-volume"
      },
      {
        name = "dummy-sidecar2-volume"
      }
    ]

    containers = [
      {
        name = "cloudrun-tf-python-example-logging-enabled"
        image = var.image
        resources = {
          limits = {
            cpu    = "1"
            memory = "512Mi"
          }
        }
        ports = {
          container_port = 8080
        }
        env = [
          {
            name = "MY_ENV_VAR1"
            value = "my_value"
          },
          {
            name = "DD_SERVERLESS_LOG_PATH"
            value = "main-app-path-should-not-be-used" # user-provided logging path should be ignored regardless of logging flag
          }
        ]
        volume_mounts = [
          {
            name = "test-volume" # volume_mount check: path should be ignored
            mount_path = "/shared-volume"
          },
          {
            name = "dd-shared-volume" # volume_mount check: name should be ignored
            mount_path = "/test-volume2"
          },
          {
            name = "good-volume" # volume_mount check: should be added
            mount_path = "/good-volume"
          }
        ]
      },
      {
        name = "datadog-sidecar" # sidecar name check: should be ignored
        image = "hi"
      }, 
      {
        name = "datadog-side" # sidecar name check: should not be ignored
        image = "hello"
      }, 
      {
        name = "other-container"
        image = "us-docker.pkg.dev/cloudrun/container/hello"
        volume_mounts = [
          {
            name = "test-volume"
            mount_path = "/shared-volume"
          }
        ]
        #container-level env var check: should be set to true bc module says enable logging

      }    
    ]
    scaling = {
      min_instance_count = 1
      max_instance_count = 1
    }
  }

  traffic = [
    {
      percent = 100
      type = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
    }
  ]

  scaling = {
    min_instance_count = 1

  }

}


## When logging is disabled:
# - The module should add the Datadog sidecar to the service (overriding the user-provided sidecar if applicable)
# - The module should add all user-provided volumes to the service
# - The module should add all user-provided volume_mounts to the service
# - The module should not add Datadog logging path to the service if set in template.containers.env or datadog_sidecar.env_vars
module "logging_disabled" {
  source = "../../"
  name = "cloudrun-test-user-input-kept-when-logging-disabled"
  location = var.region
  deletion_protection = false

  datadog_api_key = var.datadog_api_key
  datadog_site = "datadoghq.com"
  datadog_service = "cloudrun-tf-disabled-logging-structs"
  datadog_version = "1.0.0"
  datadog_tags = ["test:tag-example", "foo:tag-example-2"]
  datadog_env = "serverless"
  datadog_enable_logging = false
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
    env_vars = [
      {
        name = "DD_SERVERLESS_LOG_PATH"
        value = "path-should-not-be-used" # user-provided logging path should be ignored still, regardless of logging flag
      }
    ]
    health_port = 5555
  }

  template = {
    labels = {
      "my_label" = "test_label"
    }
    volumes = [
      {
        name = "test-volume"
        empty_dir = {
          medium = "MEMORY"
          size_limit = "100Mi"
        }
      },
      {
        name = "dd-shared-volume" # will be added and not ignored because logging is disabled
        empty_dir = {
          medium = "MEMORY"
          size_limit = "100Mi"
        }
      },
      {
        name = "good-volume"
      },
      {
        name = "dummy-sidecar2-volume"
      }
    ]

    containers = [
      {
        name = "cloudrun-tf-python-example-logging-disabled"
        image = var.image
        resources = {
          limits = {
            cpu    = "1"
            memory = "512Mi"
          }
        }
        ports = {
          container_port = 8080
        }
        env = [
          {
            name = "MY_ENV_VAR1"
            value = "my_value"
          },
          {
            name = "DD_SERVERLESS_LOG_PATH"
            value = "main-app-path-should-not-be-used" # user-provided logging path should be ignored regardless of logging flag
          }
        ]
        volume_mounts = [
          {
            name = "test-volume" # volume_mount check: should be ignored
            mount_path = "/shared-volume"
          },
          {
            name = "dd-shared-volume" # volume_mount check: should be ignored
            mount_path = "/test-volume2"
          },
          {
            name = "good-volume" # volume_mount check: should be added
            mount_path = "/good-volume"
          }
        ]
      },
      {
        name = "dd-sidecar" # sidecar image check: should not be ignored bc different name
        image = "gcr.io/datadoghq/serverless-init:latest"
        resources = {
          limits = {
            cpu = "1"
            memory = "512Mi"
          }
        }
      },
      {
        name = "datadog-sidecar" # sidecar image check: should be ignored bc name is overlapped
        image = "gcr.io/datadoghq/serverless-init:latest"
      }
    ]
    scaling = {
      min_instance_count = 1
      max_instance_count = 1
    }
  }

  traffic = [
    {
      percent = 100
      type = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
    }
  ]

  scaling = {
    min_instance_count = 1

  }

}


  # IAM Member to allow public access (optional, adjust as needed)
resource "google_cloud_run_service_iam_member" "invoker_logging_enabled" {
  service  = module.logging_enabled.name
  location = module.logging_enabled.location
  role     = "roles/run.invoker"
  member   = "allUsers"
}

resource "google_cloud_run_service_iam_member" "invoker_logging_disabled" {
  service  = module.logging_disabled.name
  location = module.logging_disabled.location
  role     = "roles/run.invoker"
  member   = "allUsers"
}