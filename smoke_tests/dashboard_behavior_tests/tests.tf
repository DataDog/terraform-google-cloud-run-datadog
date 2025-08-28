# Unless explicitly stated otherwise all files in this repository are licensed under the Apache-2.0 License.
# This product includes software developed at Datadog (https://www.datadoghq.com/) Copyright 2025 Datadog, Inc.

provider "google" {
  project = var.project
  region  = var.region
}


# Logs injection correlating traces or not: when DD_LOGS_INJECTION is true, logs should be injected into the trace
# manually setting DD_LOGS_INJECTION to false in the main container should not inject logs into the trace
module "module-logs-injection" {
  source = "../../"
  name = "cloudrun-test-logs-injection"
  location = var.region
  deletion_protection = false

  datadog_service = "cloudrun-logs-injection"
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
        { # set DD_LOGS_INJECTION to false hence no log-trace correlation to see in the dashboard
            name = "app-container-without-tracing-logs-correlation"
            image = "europe-west1-docker.pkg.dev/datadog-serverless-gcp-demo/cloud-run-source-deploy/cloud-run-tftest-node:latest"
            env = [
            {
                name = "DD_LOGS_INJECTION"
                value = "false"
            }
            ]
            ports = {
                container_port = 8080
            }
        }
        
    ]
  }

}

# logging enabled or not: when datadog_enable_logging is false, no logs should apppear in dashboard
module "module-no-logs" {
  source = "../../"
  name = "cloudrun-test-no-logs"
  location = var.region
  deletion_protection = false

  datadog_service = "cloudrun-test-no-logs"
  datadog_api_key = var.datadog_api_key
  datadog_site = "datadoghq.com"
  datadog_version = "1.0.0"
  datadog_env = "serverless"
  datadog_enable_logging = false
  datadog_log_level = "debug"


  datadog_sidecar = {
    #uses default sidecar image, name, resources, healthport
    image = "gcr.io/datadoghq/serverless-init:latest"
    name = "datadog-sidecar"
    health_port = 5555
  }

  template = {
    containers = [
        { # deploying should see no logs in the dashboard
            name = "app-container-no-logging"
            image = "europe-west1-docker.pkg.dev/datadog-serverless-gcp-demo/cloud-run-source-deploy/cloud-run-tftest-node:latest"
            ports = {
                container_port = 8080
            }
        }
        
    ]
  }

}



resource "google_cloud_run_service_iam_member" "invoker_logs_injection" {
  service  = module.module-logs-injection.name
  location = module.module-logs-injection.location
  role     = "roles/run.invoker"
  member   = "allUsers"
}

resource "google_cloud_run_service_iam_member" "invoker_no_logs" {  
  service  = module.module-no-logs.name
  location = module.module-no-logs.location
  role     = "roles/run.invoker"
  member   = "allUsers"
}