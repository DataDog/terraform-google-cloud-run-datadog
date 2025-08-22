### Testing examples of different containers and volumes, infrastructure component setups (user-module value prioritization tested in logging_flag.tf)
# - setting containers
# - setting volumes
# - setting volume_mounts
# - setting sidecar configurations
# - setting logging configurations
# - setting startup probe configurations
# - setting traffic configurations
# - setting scaling configurations
## Just to see that these can be deployed, so no outputs needed


# no main container
module "no-main-container" {
  source = "../../"
  name = "cloudrun-test-no-main-container"
  location = var.region
  deletion_protection = false

  datadog_api_key = var.datadog_api_key
  datadog_site = "datadoghq.com"
  datadog_service = "cloudrun-test-no-main-container"
  datadog_sidecar = {
    #uses default sidecar image, name, resources, healthport
    image = "gcr.io/datadoghq/serverless-init:latest"
    name = "datadog-sidecar"
    health_port = 5555
  }

  template = {
  }

}

# minimum required setup
module "minimum-required" {
  source = "../../"
  name = "cloudrun-test-minimum-required"
  location = var.region
  deletion_protection = false

  datadog_api_key = var.datadog_api_key
  datadog_site = "datadoghq.com"
  datadog_service = "cloudrun-barebones"
  datadog_sidecar = {
    #uses default sidecar image, name, resources, healthport
  }

  template = {
    containers = [
      {
        name = "cloudrun-barebones-main-container"
        image = var.image
        ports = {
          container_port = 8080
        }
      }
    ]
  }

}

# setting as many of all possible parameters as possible
module "many-parameters" {
  source = "../../"
  name = "cloudrun-test-many-parameters"
  location = var.region
  deletion_protection = false
  annotations = {
    "my-annotation" = "my-value"
  }
  ingress = "INGRESS_TRAFFIC_ALL"

  

  datadog_api_key = var.datadog_api_key
  datadog_site = "datadoghq.com"
  datadog_service = "cloudrun-test-many-parameters"
  datadog_sidecar = {
    #sets sidecar image, name, resources, healthport, env_vars, probe resources
    image = "gcr.io/datadoghq/serverless-init:latest"
    name = "datadog-sidecar"
    health_port = 1234
    resources = {
      limits = {
        cpu = "1"
        memory = "1024Mi"
      }
    }
    env_vars = [
      {
        name = "MY_ENV_VAR1"
        value = "my_value"
      },
    ]
    startup_probe = {
      failure_threshold = 3
      initial_delay_seconds = 2
      period_seconds = 10
      timeout_seconds = 5
    }
  }


  template = {
    containers = [
      {
        name = "cloudrun-many-parameters-main-container"
        image = var.image
        ports = {
          container_port = 8080
        }
        env = [
          {
            name = "MY_ENV_VAR1"
            value = "my_value"
          },
        ]
        volume_mounts = [
          {
            name = "random-volume-1"
            mount_path = "/random-volume-1"
          },
        ]

        startup_probe = {
          failure_threshold = 3
          initial_delay_seconds = 0
          period_seconds = 10
          timeout_seconds = 5
          tcp_socket = {
            port = 8080
          }
        }
        liveness_probe = {
          failure_threshold = 3
          initial_delay_seconds = 0
          period_seconds = 10
          timeout_seconds = 5
          http_get = {
            path = "/health"
            port = 8080
          }
        }

      },
    ]
    volumes = [
      {
        name = "random-volume-1"
        empty_dir = {
          medium = "MEMORY"
        }
      },
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
    max_instance_count = 1
  }
}

  # IAM Member to allow public access (optional, adjust as needed)
resource "google_cloud_run_service_iam_member" "invoker_no-main-container" {
  service  = module.no-main-container.name
  location = module.no-main-container.location
  role     = "roles/run.invoker"
  member   = "allUsers"
}

resource "google_cloud_run_service_iam_member" "invoker_minimum-required" {
  service  = module.minimum-required.name
  location = module.minimum-required.location
  role     = "roles/run.invoker"
  member   = "allUsers"
}

resource "google_cloud_run_service_iam_member" "invoker_many-parameters" {
  service  = module.many-parameters.name
  location = module.many-parameters.location
  role     = "roles/run.invoker"
  member   = "allUsers"
}