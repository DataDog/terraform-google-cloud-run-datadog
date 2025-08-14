# # # TESTING FOR: DD_SERVICE, DD_SERVERLESS_LOG_PATH env vars on container (var.templates.containers.env) and service (var.datadog_service) level
# # - when DD_SERVICE provided in template.containers.env, it should override the module-computed value
# # - when DD_SERVICE not provided in template.containers.env, it should use the module-computed value

# # - when DD_SERVERLESS_LOG_PATH is provided on container-level template.containers.env, it should be ignored, and the module-computed value should be used

# test that when provided on module, module-set DD_SERVICE should override the cloud run service name
# test that when var.datadog_logging_path is provided on module, it should be used for DD_SERVERLESS_LOG_PATH env var in main containers, and in sidecar container
module "module-level-override" {
  source = "../../"
  name = "cloudrun-sidecar-user-dd-service"
  location = var.location
  deletion_protection = false

  datadog_service = "service-value-used"
  datadog_api_key = var.datadog_api_key
  datadog_site = "datadoghq.com"
  datadog_version = "1.0.0"
  datadog_env = "serverless"
  datadog_enable_logging = true
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
        {
            name = "app-container"
            image = "europe-west1-docker.pkg.dev/datadog-cloud-run-v2-wrapper/datadog-cloud-run-v2-wrapper-test/datadog-cloud-run-v2-wrapper-test:latest"
        }
    ]
  }

}

# test that when var.datadog_service is left empty on module, it should default to cloud run service name
#test that when DD_SERVERLESS_LOG_PATH is left empty on module, it should default to /shared-volume/logs/*.log
module "module-name-default" {
  source = "../../"
  name = "service-name-used-in-dd-service-var"
  location = var.location
  deletion_protection = false

#   datadog_service = #should not be provided, will default to service name of module
  datadog_api_key = var.datadog_api_key
  datadog_site = "datadoghq.com"
  datadog_version = "1.0.0"
  datadog_env = "serverless"
  datadog_enable_logging = true
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
    ]
  }

}


#test container modifications: 
# when DD_SERVICE is provided in template.containers.env, the container-level value should be used in main containers
# when DD_SERVERLESS_LOG_PATH is provided in template.containers.env, it should be ignored, and the module-computed var.datadog_logging_path should be used in main and sidecar containers
module "container-level-override" {
  source = "../../"
  name = "cloudrun-sidecar-user-dd-service"
  location = var.location
  deletion_protection = false

  datadog_service = "service-value-not used"
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
                {name = "DD_SERVICE", value = "app-service-value-used"}, # should be used because provided in var.template.containers[*].env, more specific
                {name = "DD_SERVERLESS_LOG_PATH", value = "logging-path-that-should-be-ignored"} # should be ignored, because module does not support user-setting this var in var.template.containers.env
            ]
        },
    ]
  }

}




resource "google_cloud_run_service_iam_member" "invoker_dd_module_level_override" {
  service  = module.module-level-override.name
  location = module.module-level-override.location
  role     = "roles/run.invoker"
  member   = "allUsers"
}

resource "google_cloud_run_service_iam_member" "invoker_dd_module_name_default" {
  service  = module.module-name-default.name
  location = module.module-name-default.location
  role     = "roles/run.invoker"
  member   = "allUsers"
}

resource "google_cloud_run_service_iam_member" "invoker_dd_container_level_override" {
  service  = module.container-level-override.name
  location = module.container-level-override.location
  role     = "roles/run.invoker"
  member   = "allUsers"
}