provider "google" {
  project = var.project
  region  = var.region
}

module "datadog-cloud-run-v2-wrapper" {
  source = "../../../"
  name = var.name
  location = var.location
  deletion_protection = false

  dd_api_key = var.datadog_api_key
  dd_site = "datadoghq.com" #default
  dd_service = "cloudrun-tf-python-hello"
  dd_version = "1.0.0"
  dd_tags = ["test:tag-example", "foo:tag-example-2"]
  dd_env = "serverless"
  dd_logs_injection = true
  dd_logging_path = "/shared-volume/logs/*.log"

  dd_sidecar = {
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
    labels = {
      "my_label" = "test_wrapper_with_all_fields"
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
