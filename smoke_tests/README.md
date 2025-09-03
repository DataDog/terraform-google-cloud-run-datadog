# Testing Plan

There are three main areas for testing:

1. **Datadog environment variables**: verifying correct values and override behavior.
2. **Infrastructure validation**: resource, containers, volumes, and volume mounts created by the module.
3. **End-to-end functionality**: The variables set produce the expected behavior visible in the Datadog dashboard (toggling traces/logging on/off, etc).

To test, cd into any of the 3 subdirectories.
* Create a [Datadog API Key](https://app.datadoghq.com/organization-settings/api-keys)
* Create a `terraform.tfvars` file
  - Set the `datadog_api_key` to the value of the key you just created
  - Set the `name` to the name of the Cloud Run UI service you want to use, and will be used to filter for the resource in Datadog
  - Set the `image` to the container image link you plan to use for your main app container
  - Set the `project` to the GCP project ID
  - Set the `region` to the region you are deploying your service to (and same region as the one used in image link)
* Run the following commands

```
terraform init
terraform plan
terraform apply
```

Confirm that the Cloud Run services were all created as expected.

Run the following commands to clean up the environment:

```
terraform destroy
```

---

## 1. Environment Variables Check

Datadog-related environment variables are injected into two types of containers:

- The **main user-provided containers**
- The **Datadog sidecar container**

### Main Containers

We test the behavior of the following variables:

#### `DD_LOGS_INJECTION`

- If `var.template.containers[*].env_vars` sets `DD_LOGS_INJECTION` to false, the Cloud Run UI will show `false` for that container regardless of `var.datadog_enable_logging` value
- If `var.template.containers[*].env_vars` sets `DD_LOGS_INJECTION` to true, the Cloud Run UI will show `true` for that container regardless of `var.datadog_enable_logging` value
- If no value is given in `var.datadog_enable_logging` and there is also no container-level input, `DD_LOGS_INJECTION` will default to `true` for all containers
- If `var.datadog_enable_logging` is set to `false` and there is also no container-level input, `DD_LOGS_INJECTION` should be `false` too for all containers

#### `DD_SERVICE`

- Container-level `DD_SERVICE` takes precedence over module's
- Setting `DD_SERVICE` at the module level should propagate to the container-level and Cloud Run UI.
- Not setting at module level should resort to using default value (Cloud Run service name) aka `var.name`

#### `DD_SERVERLESS_LOG_PATH`

- Container-level values are ignored — always use `var.datadog_logging_path`
- If not set at the module level, the default is `/shared-volume/logs/*.log`

---

### Sidecar Container

This includes testing both module-managed instrumentation variables and user-supplied customizations to the agent configuration via `var.datadog_sidecar.env`.

#### Sidecar variables managed by the module

These variables present in configuring the sidecar must **always use the module-computed value** and **must only be modified through their respective datadog_* parameters**:

- `DD_SERVICE`
- `DD_SITE`
- `DD_SERVERLESS_LOG_PATH`
- `DD_ENV`
- `DD_API_KEY`
- `DD_VERSION`
- `DD_LOG_LEVEL`
- `DD_HEALTH_PORT`

#### Instrumentation and merging behavior

- If no environment variables are provided through `var.datadog_sidecar.env`, all module-level variables are injected as given.
- If environment variables are provided through `var.datadog_sidecar.env`, all user-defined variables NOT managed by var.datadog_* parameters are surfaced in the Cloud Run UI.
- If a user attempts to redefine a module-managed variable (listed above), the module value should take be used instead.


## 2. Infrastructure Check

We must also verify the module creates and configures the infrastructure components correctly.

### Resource Deployment

- Verify multiple combinations of module inputs result in expected infrastructure.

### Sidecar Container

- Always uses the module-created container definition.
- Includes user-specified environment variables from `var.datadog_sidecar.env`.
- If a container in `var.template.containers` matches `var.datadog_sidecar.name`, it is ignored — the module's sidecar takes precedence.

### Volume Mounts

- If logging is enabled (`var.datadog_enable_logging = true`):
  - The shared volume mount is added to **every main app container**.
  - Any user-defined volume_mounts with the **same `name` or `mount_path`** as `var.datadog_shared_volume` are filtered out.
  - All non-conflicting user-defined volume_mounts are preserved.
- If logging is disabled (`var.datadog_enable_logging = false`):
  - We do not touch the user-defined volume_mounts.

### Volumes

- If logging is enabled (`var.datadog_enable_logging = true`):
  - A shared volume is added to the deployment template.
  - Any user-defined volume with the **same `name`** as `var.datadog_shared_volume.name` is ignored.
  - All non-conflicting user-defined volumes are preserved.
- If logging is disabled (`var.datadog_enable_logging = false`):
  - We do not touch the user-defined volumes.


## 3. Dashboard observability

Lastly, verify the module's IAC configuration exhibits expected behavior on the Datadog dashboard.

### Logs Injection

- Setting `DD_LOGS_INJECTION = false` ensures the tracing-log correlation is turned off

### Logging

- If `var.datadog_enable_logging = true`, logs show up
- If logging is disabled, no logs should appear in dashboard

