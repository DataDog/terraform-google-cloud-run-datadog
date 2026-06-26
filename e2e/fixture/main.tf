# Unless explicitly stated otherwise all files in this repository are licensed under the Apache-2.0 License.
# This product includes software developed at Datadog (https://www.datadoghq.com/) Copyright 2026 Datadog, Inc.

# E2E test stack: exercises the module exactly as a consumer would. The module
# under test (source = ../../) is the instrumentation mechanism -- APPLY here is
# what stands up the instrumented Cloud Run service, and `terraform destroy` is
# the REMOVE step verified to leave no residue.

provider "google" {
  project = var.project
  region  = var.region
}

module "datadog" {
  source              = "../../"
  name                = var.name
  location            = var.region
  deletion_protection = false

  datadog_api_key        = var.datadog_api_key
  datadog_site           = var.datadog_site
  datadog_service        = var.datadog_service
  datadog_env            = var.datadog_env
  datadog_version        = var.datadog_version
  datadog_tags           = ["one_e2e_run_id:${var.run_id}"]
  datadog_enable_logging = true

  # Pin the sidecar artifact by digest so an upstream serverless-init change
  # never turns into a red e2e run for this module.
  datadog_sidecar = {
    image = var.sidecar_image
  }

  # Freshness label set atomically at creation for the cross-repo sweeper.
  labels = {
    one_e2e_created = var.created_ts
  }

  template = {
    containers = [
      {
        name  = "app"
        image = var.workload_image
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
    scaling = {
      min_instance_count = 0
      max_instance_count = 1
    }
  }

  traffic = [
    {
      percent = 100
      type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
    }
  ]
}

# Allow unauthenticated HTTP so the test can trigger the workload over its URL.
resource "google_cloud_run_service_iam_member" "invoker" {
  project  = var.project
  location = module.datadog.location
  service  = module.datadog.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}
