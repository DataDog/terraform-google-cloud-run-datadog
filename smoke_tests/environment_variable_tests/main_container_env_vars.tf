# Unless explicitly stated otherwise all files in this repository are licensed under the Apache-2.0 License.
# This product includes software developed at Datadog (https://www.datadoghq.com/) Copyright 2025 Datadog, Inc.

# # # TESTING FOR: DD_SERVICE, DD_LOGS_INJECTION, DD_SERVERLESS_LOG_PATH env vars on container (var.templates.containers.env) and module level
# # - when DD_SERVICE provided in template.containers.env, it should override the module-computed value
# # - when DD_SERVICE not provided in template.containers.env, it should use the module-computed value
# # - when DD_SERVERLESS_LOG_PATH is provided on container-level template.containers.env, it should be ignored, and the module-computed value should be used
# # - when DD_LOGS_INJECTION is provided on container-level template.containers.env, it should override the module-computed value
# # - when DD_LOGS_INJECTION is not provided on container-level template.containers.env, module-computed value should be used

provider "google" {
  project = var.project
  region  = var.region
}

# test that when provided on module, module-set DD_SERVICE should override the cloud run service name
# test that when var.datadog_logging_path is provided on module, it should be used for DD_SERVERLESS_LOG_PATH env var in main containers, and in sidecar container
# DD_LOGS_INJECTION can be set to false at module level, and is NOT set for all containers
module "module-level-override" {
  source = "../../"
  name = "cloudrun-test-main-module-override-module-defaults"
  location = var.region
  deletion_protection = false

  datadog_service = "service-value-to-be-used-from-datadog-service-var"
  datadog_api_key = var.datadog_api_key
  datadog_site = "datadoghq.com"
  datadog_version = "1.0.0"
  datadog_env = "serverless"
  datadog_enable_logging = false
  datadog_log_level = "debug"
  datadog_logging_path = "/shared-volume/testlogs/*.log"
  datadog_shared_volume = {
    name = "dd-shared-volume"
    mount_path = "/shared-volume"
    size_limit = "500Mi"
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
    health_port = 1283
  }

  template = {
    containers = [
        { # should have a false DD_LOGS_INJECTION because module default is false
            name = "app-container"
            image = "europe-west1-docker.pkg.dev/datadog-cloud-run-v2-wrapper/datadog-cloud-run-v2-wrapper-test/datadog-cloud-run-v2-wrapper-test:latest"
        }
    ]
  }

}

# test that when var.datadog_service is left empty on module, it should default to cloud run service name
#test that when DD_SERVERLESS_LOG_PATH is left empty on module, it should default to /shared-volume/logs/*.log
# DD_LOGS_INJECTION should be true for all containers bc module default is true
module "module-name-default" {
  source = "../../"
  name = "cloudrun-test-main-module-name-default-and-service-name-used"
  location = var.region
  deletion_protection = false

#   datadog_service = #should not be provided, will default to service name of module
  datadog_api_key = var.datadog_api_key
  datadog_site = "datadoghq.com"
  datadog_version = "1.0.0"
  datadog_env = "serverless"
  # datadog_enable_logging should default to true because module default is true
  datadog_log_level = "debug"
  datadog_shared_volume = {
    name = "dd-shared-volume"
    mount_path = "/shared-volume"
    size_limit = "500Mi"
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
    health_port = 1283
  }

  template = {
    containers = [
        {
            name = "app-container"
            image = "europe-west1-docker.pkg.dev/datadog-cloud-run-v2-wrapper/datadog-cloud-run-v2-wrapper-test/datadog-cloud-run-v2-wrapper-test:latest"
        }
        # the container-level DD_LOGS_INJECTION is not set, so that the module-computed value is used (and true)
    ]
  }

}


#test container modifications: 
# when DD_SERVICE is provided in template.containers.env, the container-level value should be used in main containers
# when DD_SERVERLESS_LOG_PATH is provided in template.containers.env, it should be ignored, and the module-computed var.datadog_logging_path should be used in main and sidecar containers
# DD_LOGS_INJECTION can be set to false at container-level, and is false for that container
module "container-level-override" {
  source = "../../"
  name = "cloudrun-test-main-container-level-override"
  location = var.region
  deletion_protection = false

  datadog_service = "service-value-used-in-sidecar-env-vars"
  datadog_api_key = var.datadog_api_key
  datadog_site = "datadoghq.com"
  datadog_version = "1.0.0"
  datadog_env = "serverless"
  datadog_enable_logging = true
  datadog_log_level = "debug"
  datadog_logging_path = "/shared-volume/logs/*.log"
  datadog_shared_volume = {
    name = "dd-shared-volume"
    mount_path = "/shared-volume"
    size_limit = "500Mi"
  }


  datadog_sidecar = {
    image = "gcr.io/datadoghq/serverless-init:latest"
    name = "datadog-sidecar"
    resources = {
      limits = {
        cpu = "1"
        memory = "512Mi"
      }
    }
    health_port = 1283
  }

  template = {
    containers = [
        {
            name = "app-container"
            image = "europe-west1-docker.pkg.dev/datadog-cloud-run-v2-wrapper/datadog-cloud-run-v2-wrapper-test/datadog-cloud-run-v2-wrapper-test:latest"
            env = [
                {name = "DD_SERVICE", value = "service-value-used-from-container-in-main"}, # should be used because provided in var.template.containers[*].env, more specific
                {name = "DD_SERVERLESS_LOG_PATH", value = "logging-path-that-should-be-ignored"}, # should be ignored, because module does not support user-setting this var in var.template.containers.env
                {name = "DD_LOGS_INJECTION", value = "false"}, # should be false because provided in var.template.containers[*].env, more specific
            ]
        },
    ]
  }

}


resource "google_cloud_run_service_iam_member" "invoker_dd_main_module_level_override" {
  service  = module.module-level-override.name
  location = module.module-level-override.location
  role     = "roles/run.invoker"
  member   = "allUsers"
}

resource "google_cloud_run_service_iam_member" "invoker_dd_main_module_name_default" {
  service  = module.module-name-default.name
  location = module.module-name-default.location
  role     = "roles/run.invoker"
  member   = "allUsers"
}

resource "google_cloud_run_service_iam_member" "invoker_dd_main_container_level_override" {
  service  = module.container-level-override.name
  location = module.container-level-override.location
  role     = "roles/run.invoker"
  member   = "allUsers"
}