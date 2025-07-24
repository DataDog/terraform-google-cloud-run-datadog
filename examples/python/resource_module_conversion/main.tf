# Example: resource to module conversion without destroying via moved block status
# cloud run resource invocation has 2 containers (2nd one is main ingress, identified by exposed port)
# moved block status can move from resource to module and vice versa IF
# # # the name field in the resource is the same as the name passed into the module

provider "google" {
  project = var.project
  region  = var.region
}

module "datadog-cloud-run-v2-wrapper" {
  source = "../../../"
  name = var.name # For moving, MUST MATCH NAME PASSED INTO RESOURCE
  location = var.location
  deletion_protection = false

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
      {
        name = "test-volume-2"
        empty_dir = {
          medium = "MEMORY"
          size_limit = "100Mi"
        }
      },

    ]

    containers = [
      {
        name = "tf-cloudrun-python-test"
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
            name = "MY_ENV_VAR"
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

# resource "google_cloud_run_v2_service" "datadog-cloud-run-service" {
#   name     = var.name #For moving, MUST MATCH NAME PASSED INTO MODULE
#   location = var.location
#   deletion_protection = false
  
#   template {
#     labels = {
#       "my_label" = "test_wrapper_with_all_fields"
#     }

#     volumes {
#       name = "test-volume"
#       empty_dir {
#         medium = "MEMORY"
#         size_limit = "100Mi"
#       }
#     }

#     volumes {
#       name = "test-volume-2"
#       empty_dir {
#         medium = "MEMORY"
#         size_limit = "100Mi"
#       }
#     }

#     containers {
#       name = "tf-cloudrun-python-test"
#       image = var.image
#       resources {
#         limits = {
#           cpu = "1"
#           memory = "512Mi"
#         }
#       }
#       ports {
#         container_port = 8080
#       }
#       env {
#         name = "MY_ENV_VAR"
#         value = "my_value"
#       }
#       env {
#         name = "ANOTHER_ENV_VAR"
#       }
#     }
#     scaling {
#         min_instance_count = 1
#         max_instance_count = 1
#       }
#   }
#   scaling {
#     min_instance_count = 1
#   }
  
# }
 
moved{
  ## moving from resource to module
  from = google_cloud_run_v2_service.datadog-cloud-run-service
  to = module.datadog-cloud-run-v2-wrapper.google_cloud_run_v2_service.this

  ## moving from module to resource
  # from = module.datadog-cloud-run-v2-wrapper.google_cloud_run_v2_service.this
  # to = google_cloud_run_v2_service.datadog-cloud-run-service
}


  # IAM Member to allow public access (optional, adjust as needed)
resource "google_cloud_run_service_iam_member" "invoker" { //todo: make roles more customizable if needed
  service  = module.datadog-cloud-run-v2-wrapper.name # module declaration
  location = module.datadog-cloud-run-v2-wrapper.location
  # service  = google_cloud_run_v2_service.datadog-cloud-run-service.name # resource declaration
  # location = google_cloud_run_v2_service.datadog-cloud-run-service.location
  role     = "roles/run.invoker"
  member   = "allUsers"
}
