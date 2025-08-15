# # # TESTING FOR: sidecar environment variables, priority between user input and module-computed values
# # - all module-controlled env vars should be ignored if user provides them in var.datadog_sidecar.env_vars
# # - i.e. DD_API_KEY, DD_SITE, DD_SERVICE, DD_HEALTH_PORT, DD_VERSION, DD_ENV, DD_TAGS, DD_LOG_LEVEL, DD_SERVERLESS_LOG_PATH
# # - user-provided env vars for values not in the module-controlled list should be reflected in outputs and UI

# Tests when user provides env vars for sidecar-instrumentation, all module-controlled env vars should be ignored
# Tests when user provides env vars for agent-configuration, the non-module-controlled env vars should be reflected in outputs and UI
module "sidecar-user-env-vars-test" {
    source = "../../"
    name = "cloudrun-sidecar-user-env-vars-test"
    location = var.region
    deletion_protection = false

    datadog_service = "sidecar-env-vars-test"
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
        env_vars = [
            {
                name = "DD_API_KEY"
                value = "user-value-should-not-be-used"
            },
            {
                name = "DD_SITE"
                value = "user-value-should-not-be-used"
            },
            {
                name = "DD_SERVICE"
                value = "user-value-should-not-be-used"
            },
            {
                name = "DD_HEALTH_PORT"
                value = "user-value-should-not-be-used"
            },
            {
                name = "DD_VERSION"
                value = "user-value-should-not-be-used"
            },
            {
                name = "DD_ENV"
                value = "user-value-should-not-be-used"
            },
            {
                name = "DD_TAGS"
                value = "user-value-should-not-be-used"
            },
            {
                name = "DD_LOG_LEVEL"
                value = "user-value-should-not-be-used"
            },
            {
                name = "DD_SERVERLESS_LOG_PATH"
                value = "user-value-should-not-be-used"
            },
            {
                name = "DD_LOGS_INJECTION"
                value = "user-value-should-not-be-used"
            },
            {
                name = "DD_TRACE_ENABLED"
                value = "not a field so ADD THIS"
            },
            {
                name = "NEW_ENV_VAR"
                value = "user-value-should-be-used"
            }
        ]
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


resource "google_cloud_run_service_iam_member" "invoker_dd_sidecar_user_env_vars_test" {
    service  = module.sidecar-user-env-vars-test.name
    location = module.sidecar-user-env-vars-test.location
    role     = "roles/run.invoker"
    member   = "allUsers"
}