# Testing Plan

There are three main areas for testing:

1. **Datadog environment variables**: verifying correct values and override behavior.
2. **Infrastructure validation**: resource, containers, volumes, and volume mounts created by the module.
3. **End-to-end functionality**: The variables set produce the expected behavior visible in the Datadog dashboard (toggling traces/logging on/off, etc).

---

## 1. Environment Variables Check

Datadog-related environment variables are injected into two types of containers:

- The **main user-provided containers**
- The **Datadog sidecar container**

### Main Containers

We test the behavior of the following variables:

#### `DD_LOGS_INJECTION`

- if `var.template.containers[*].env_vars` sets `DD_LOGS_INJECTION` to false, the Cloud Run UI will show false for that container regardless of `var.datadog_enable_logging`
- if `var.template.containers[*].env_vars` sets `DD_LOGS_INJECTION` to true, the Cloud Run UI will show true for that container regardless of `var.datadog_enable_logging` 
- if no value is given in `var.datadog_enable_logging` and no container-level input, `DD_LOGS_INJECTION` will be default to `true` for all containers
- if `var.datadog_enable_logging` is set to `false` and no container-level input, `DD_LOGS_INJECTION` should be `false` too for all containers

#### `DD_SERVICE`

- container-level `DD_SERVICE` takes precednece over module's
- setting at the module level should propagate to the container-level and Cloud Run UI.
- not setting at module level should use default derived from `var.name`

#### `DD_SERVERLESS_LOG_PATH`

- If not set at the module level, the default is `/shared-volume/logs/*.log`.
- Container-level values are ignored — always use `var.datadog_logging_path`.

---

### Sidecar Container

This includes testing both module-managed instrumentation variables and user-supplied customizations via `var.datadog_sidecar.env_vars`.

#### Variables managed by the module

These must **always use the module-computed value** and **must not be overridden**:

- `DD_SERVICE`
- `DD_SITE`
- `DD_SERVERLESS_LOG_PATH`
- `DD_ENV`
- `DD_API`
- `DD_VERSION`
- `DD_LOG_LEVEL`
- `DD_LOGS_INJECTION`
- `DD_HEALTH_PORT`

#### Instrumentation and merging behavior

- If no `var.datadog_sidecar.env_vars` are provided, all module-level variables are injected as given.
- If `var.datadog_sidecar.env_vars` is provided, all user-defined variables NOT managed by var.datadog_** parameters are surfaced in the Cloud Run UI.
- If a user attempts to redefine a module-managed variable (listed above), the module value should take precedence.


## 2. Infrastructure Check

We must also verify the module creates and configures the infrastructure components correctly.

### Resource Deployment

- Verify multiple combinations of module inputs result in expected infrastructure.

### Sidecar Container

- Always uses the module-created container definition.
- Includes user-specified environment variables from `var.datadog_sidecar.env_vars`.
- If a container in `var.template.containers` matches `var.datadog_sidecar.name`, it is ignored — the module's sidecar takes precedence.

### Volume Mounts

- If logging is enabled (var.datadog_enable_logging = `true`):
  - The shared volume mount is added to **every main app container**.
  - Any user-defined volume_mounts with the **same `name` or `mount_path`** as `var.datadog_shared_volume` are filtered out.
  - All non-conflicting user-defined volume_mounts are preserved.
- If logging is disabled (var.datadog_enable_logging = `false`):
  - We do not touch the user-defined volume_mounts.

### Volumes

- If logging is enabled (var.datadog_enable_logging = `true`):
  - A shared volume is added to the deployment template.
  - Any user-defined volume with the **same `name`** as `var.datadog_shared_volume.name` is ignored.
  - All non-conflicting user-defined volumes are preserved.
- If logging is disabled (var.datadog_enable_logging = `true`):
  - We do not touch the user-defined volumes.


## 3. Dashboard observability

Lastly, verify the IAC confiugration exhibits expected behavior on the Datadog dashboard.

### Logs Injection

- Setting Logs Injection to false ensures the tracing-log correlation is turned off

### Logging

- If `var.datadog_enable_logging = true`, logs show up
- If logging is disabled, no logs should appear in dashboard

### Tracing
- If `var.datadog_enable_tracing = true`, traces appear in the dashboard
- If tracing is disabled, no traces should show up