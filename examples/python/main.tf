provider "google" {
  project = var.project
  region  = var.region
}

module "datadog-cloud-run-v2-wrapper" {
  source = "../../"
  name = var.name
  location = var.location
  deletion_protection = false

  datadog_api_key = var.datadog_api_key
  datadog_site = "datadoghq.com"
  datadog_service = "cloudrun-tf-python-hello"
  datadog_version = "1.0.0"
  datadog_tags = ["test:tag-example", "foo:tag-example-2"]
  datadog_env = "serverless"
  datadog_enable_logging = true
  datadog_log_level = "debug"
  datadog_logging_path = "/shared-volume/logs/*.log"


  datadog_sidecar = {
    # uses default sidecar image, name, resources, healthport
    resources = {
      limits = {
        cpu = "1"
        memory = "512Mi"
      }
    }
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

    ]

    containers = [
      {
        name = "cloudrun-tf-python-example"
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
            name = "ANOTHER_ENV_VAR"
          }
        
        ]
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

  }

}



  # IAM Member to allow public access (optional, adjust as needed)
resource "google_cloud_run_service_iam_member" "invoker" {
  service  = module.datadog-cloud-run-v2-wrapper.name
  location = module.datadog-cloud-run-v2-wrapper.location
  role     = "roles/run.invoker"
  member   = "allUsers"
}
