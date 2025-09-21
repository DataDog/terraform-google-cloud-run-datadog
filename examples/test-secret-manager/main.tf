module "cloud_run_datadog" {
  source = "../.."

  name     = "test-secret-manager"
  project  = "test-project"
  location = "us-central1"

  datadog_api_key = "test-api-key"

  template = {
    containers = [
      {
        name  = "main"
        image = "us-docker.pkg.dev/cloudrun/container/hello"

        env = [
          {
            name  = "PLAIN_ENV_VAR"
            value = "plain-value"
          },
          {
            name = "SECRET_ENV_VAR"
            value_source = {
              secret_key_ref = {
                secret  = "projects/test-project/secrets/my-secret"
                version = "latest"
              }
            }
          }
        ]
      }
    ]
  }
}

output "container_env" {
  value = module.cloud_run_datadog.template.containers[1].env
}