# Unless explicitly stated otherwise all files in this repository are licensed under the Apache-2.0 License.
# This product includes software developed at Datadog (https://www.datadoghq.com/) Copyright 2026 Datadog, Inc.

### Tests for Cloud SQL volume mounts: verify that when a Cloud SQL volume is added, it is correctly mounted
### on the main app container

module "cloudsql-volume" {
  source              = "../../"
  name                = "cloudrun-test-cloudsql-volume"
  location            = var.region
  deletion_protection = false

  datadog_api_key        = var.datadog_api_key
  datadog_site           = "datadoghq.com"
  datadog_service        = "cloudrun-test-cloudsql-volume"
  datadog_enable_logging = true
  datadog_shared_volume = {
    name       = "dd-shared-volume"
    mount_path = "/shared-volume"
  }
  datadog_sidecar = {
    image       = "gcr.io/datadoghq/serverless-init:latest"
    name        = "datadog-sidecar"
    health_port = 5555
  }

  template = {
    containers = [
      {
        name  = "app"
        image = var.image
        ports = {
          container_port = 8080
        }
        volume_mounts = [
          {
            name       = "cloudsql"
            mount_path = "/cloudsql"
          },
          {
            name       = "extra-volume"
            mount_path = "/extra"
          },
        ]
      },
    ]
    volumes = [
      {
        name = "cloudsql"
        cloud_sql_instance = {
          instances = [var.cloudsql_instance]
        }
      },
      {
        name = "extra-volume"
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
}

resource "google_cloud_run_v2_service_iam_member" "invoker_cloudsql-volume" {
  name     = module.cloudsql-volume.name
  location = module.cloudsql-volume.location
  role     = "roles/run.invoker"
  member   = "allUsers"
}
