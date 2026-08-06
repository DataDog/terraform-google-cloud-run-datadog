# Unless explicitly stated otherwise all files in this repository are licensed under the Apache-2.0 License.
# This product includes software developed at Datadog (https://www.datadoghq.com/) Copyright 2025 Datadog, Inc.

locals {
  module_version  = "2_2_0"
  datadog_service = var.datadog_service != null ? var.datadog_service : var.name
  # Tracer copy volume mount path used by dd-lib-*-init and language env vars.
  tracer_volume_name       = "datadog-tracer"
  tracer_volume_mount_path = "/datadog-lib"
  apm_enabled              = var.datadog_apm_instrumentation != null
  using_disk_medium        = local.apm_enabled ? var.datadog_apm_instrumentation.volume_medium == "DISK" : false
  injection_mode_tag       = "_dd.injection.mode:serverless-single-lang"
  tracer_sidecar_name = local.apm_enabled ? (
    "tracer-sidecar-${var.datadog_apm_instrumentation.language}"
  ) : null

  tracer_ready_probe = local.apm_enabled ? {
    tcp_socket        = { port = var.datadog_apm_instrumentation.ready_port }
    period_seconds    = 1
    timeout_seconds   = 1
    failure_threshold = 120
  } : null
  # Matches $REPO in dd-lib-*-init copy-lib.sh (marker: $TARGET_PATH/.$REPO-copy-finished).
  tracer_repo_name = local.apm_enabled ? ({
    java   = "dd-trace-java"
    js     = "dd-trace-js"
    python = "dd-trace-py"
    dotnet = "dd-trace-dotnet"
    ruby   = "dd-trace-rb"
    php    = "dd-trace-php"
  })[var.datadog_apm_instrumentation.language] : null
  tracer_copy_finished_marker = local.apm_enabled ? "${local.tracer_volume_mount_path}/.${local.tracer_repo_name}-copy-finished" : null
  # Listener server to mark when copy is done
  tracer_probe_server = "/datadog-init/probe-server"
  # Native env vars for Single-Language SSI (mirrors admission-controller lib injection).
  apm_env_map = {
    java = {
      JAVA_TOOL_OPTIONS = " -javaagent:${local.tracer_volume_mount_path}/dd-java-agent.jar -XX:OnError=${local.tracer_volume_mount_path}/java/continuousprofiler/tmp/dd_crash_uploader.sh -XX:ErrorFile=${local.tracer_volume_mount_path}/java/continuousprofiler/tmp/hs_err_pid_%p.log"
    }
    js = {
      NODE_OPTIONS = " --require=${local.tracer_volume_mount_path}/node_modules/dd-trace/init"
    }
    python = {
      PYTHONPATH                                   = "${local.tracer_volume_mount_path}/"
      DD_INJECT_EXPERIMENTAL_OVERRIDE_USER_DDTRACE = "true" // q: this might be dangerous. are there alternatives?
    }
    dotnet = {
      CORECLR_ENABLE_PROFILING = "1"
      CORECLR_PROFILER         = "{846F5F1C-F9AE-4B07-969E-05C26BC060D8}"
      CORECLR_PROFILER_PATH    = "${local.tracer_volume_mount_path}/Datadog.Trace.ClrProfiler.Native.so"
      DD_DOTNET_TRACER_HOME    = local.tracer_volume_mount_path
      DD_TRACE_LOG_DIRECTORY   = "${local.tracer_volume_mount_path}/logs"
      LD_PRELOAD               = "${local.tracer_volume_mount_path}/continuousprofiler/Datadog.Linux.ApiWrapper.x64.so"
    }
    ruby = {
      RUBYOPT = " -r${local.tracer_volume_mount_path}/auto_inject"
    }
    php = {
      PHP_INI_SCAN_DIR       = "${local.tracer_volume_mount_path}/linux-gnu/loader"
      DD_LOADER_PACKAGE_PATH = local.tracer_volume_mount_path
    }
  }

  apm_language_env_vars = local.apm_enabled ? lookup(
    local.apm_env_map,
    var.datadog_apm_instrumentation.language,
    {},
  ) : {}

  # Base env vars the module always owns
  module_controlled_env_vars = concat(
    [
      "DD_API_KEY",
      "DD_SITE",
      "DD_SERVICE",
      "DD_HEALTH_PORT",
      "DD_VERSION",
      "DD_ENV",
      "DD_TAGS",
      "DD_LOG_LEVEL",
      "DD_SERVERLESS_LOG_PATH",
      "FUNCTION_TARGET",
      "DD_LOGS_INJECTION", # this is not an env var needed on the sidecar anyways
    ],
    # these vars are appended only when datadog_apm_instrumentation is enabled
    local.apm_enabled ? concat(
      ["DD_TRACE_ENABLED"],
      keys(local.apm_language_env_vars),
    ) : [],
  )


  ### Variables to handle input checks and infrastructure overrides (volume, volume_mount, sidecar container)
  # User-check 1: use this to override user's var.template.volumes and remove the shared volume if shared_volume already exists and logging is enabled, else keep user's volumes
  volumes_without_shared_volume = var.datadog_enable_logging ? [
    for v in coalesce(var.template.volumes, []) : v
    if v.name != var.datadog_shared_volume.name
  ] : coalesce(var.template.volumes, [])

  # User-check 2: check if sidecar container already exists and remove it from the var.template.containers list if it does (to be overridden by module's instantiation)
  containers_without_sidecar = [
    for c in coalesce(var.template.containers, []) : c
    if c.name != var.datadog_sidecar.name
  ]

  # User-check 3: check for each provided container (ignoring sidecar if provided) the volume mounts and if logging is enabled, exclude all volume mounts with same name OR path as the shared volume
  all_volume_mounts = flatten([
    for c in coalesce(local.containers_without_sidecar, []) :
    coalesce(c.volume_mounts, [])
  ])

  # filter out volume mounts with same name or path as the shared volume only if logging is enabled
  filtered_volume_mounts = var.datadog_enable_logging ? [
    for vm in coalesce(local.all_volume_mounts, []) :
    vm if !(vm.name == var.datadog_shared_volume.name || vm.mount_path == var.datadog_shared_volume.mount_path)
  ] : local.all_volume_mounts

  # User-check 4: merge env vars for sidecar-instrumentation with user-provided env vars for agent-configuration
  # (ignore any module-controlled env vars that user provides in var.datadog_sidecar.env)
  required_module_sidecar_env_vars = {
    DD_API_KEY     = var.datadog_api_key
    DD_SITE        = var.datadog_site
    DD_SERVICE     = local.datadog_service
    DD_HEALTH_PORT = tostring(var.datadog_sidecar.health_port)
  }
  # When SSI is enabled, always include the injection-mode tag (append to user tags if any).
  datadog_tags_effective = local.apm_enabled ? concat(
    coalesce(var.datadog_tags, []),
    [local.injection_mode_tag],
  ) : var.datadog_tags
  shared_env_vars = merge(
    { DD_SERVICE = local.datadog_service },
    var.datadog_version != null ? { DD_VERSION = var.datadog_version } : {},
    var.datadog_env != null ? { DD_ENV = var.datadog_env } : {},
    local.datadog_tags_effective != null ? { DD_TAGS = join(",", local.datadog_tags_effective) } : {},
    local.apm_enabled ? { DD_TRACE_ENABLED = "true" } : {},
  )
  all_module_sidecar_env_vars = merge(
    local.shared_env_vars,
    local.required_module_sidecar_env_vars,
    var.datadog_log_level != null ? { DD_LOG_LEVEL = var.datadog_log_level } : {},
    var.datadog_enable_logging ? { DD_SERVERLESS_LOG_PATH = var.datadog_logging_path } : {},
    try(var.build_config.function_target, null) != null ? { FUNCTION_TARGET = var.build_config.function_target } : {},
  )
  agent_env_vars = [ # user-provided env vars for agent-configuration, filter out the ones that are module-controlled
    for env in coalesce(var.datadog_sidecar.env, []) : env
    if !contains(local.module_controlled_env_vars, env.name)
  ]
  all_sidecar_env_vars = concat(
    local.agent_env_vars,
    [for name, value in local.all_module_sidecar_env_vars : { name = name, value = value }]
  )
  sidecar_container = merge(
    var.datadog_sidecar,
    {
      env           = local.all_sidecar_env_vars
      volume_mounts = var.datadog_enable_logging ? [var.datadog_shared_volume] : []
      startup_probe = merge(var.datadog_sidecar.startup_probe, { tcp_socket = { port = var.datadog_sidecar.health_port } })
    },
  )
  // TODO remove this once theres an official release init image with probe-server
  tracer_init_image = local.apm_enabled ? coalesce(
    var.datadog_apm_instrumentation.tracer_init_image,
    "gcr.io/datadoghq/dd-lib-${var.datadog_apm_instrumentation.language}-init:${var.datadog_apm_instrumentation.tracer_version}",
  ) : null
  tracer_volume_mount = {
    name       = local.tracer_volume_name
    mount_path = local.tracer_volume_mount_path
  }

  tracer_sidecar = local.apm_enabled ? {
    image   = local.tracer_init_image
    name    = local.tracer_sidecar_name
    command = ["sh", "-c"]
    args = [
      "/datadog-init/copy-lib.sh ${local.tracer_volume_mount_path} && [ -f '${local.tracer_copy_finished_marker}' ] && exec ${local.tracer_probe_server} ${var.datadog_apm_instrumentation.ready_port}; echo 'datadog: tracer copy did not finish, not opening ${var.datadog_apm_instrumentation.ready_port}' >&2; exit 1",
    ]
    volume_mounts = [local.tracer_volume_mount]
    startup_probe = local.tracer_ready_probe
  } : null
}

check "logging_volume_already_exists" {
  assert {
    condition     = length(coalesce(var.template.volumes, [])) == length(local.volumes_without_shared_volume)
    error_message = "Datadog log collection is enabled and a volume with the name \"${var.datadog_shared_volume.name}\" already exists in the var.template.volumes list. This module will override the existing volume with the settings provided in var.datadog_shared_volume and use it for Datadog log collection. To disable log collection, set var.datadog_enable_logging to false."
  }
}

check "logging_path_should_be_in_shared_volume" {
  assert {
    condition     = startswith(var.datadog_logging_path, var.datadog_shared_volume.mount_path)
    error_message = "The 'datadog_logging_path' must start with the 'mount_path' defined in 'datadog_shared_volume'."
  }
}

check "sidecar_already_exists" {
  assert {
    condition     = length(coalesce(var.template.containers, [])) == length(local.containers_without_sidecar)
    error_message = "A sidecar container with the name \"${var.datadog_sidecar.name}\" already exists in the var.template.containers list. This module will override the existing container(s) with the settings provided in var.datadog_sidecar."
  }
}

check "volume_mounts_share_names_and_or_paths" {
  assert {
    condition     = length(local.filtered_volume_mounts) == length(local.all_volume_mounts)
    error_message = "Logging is enabled, and user-inputted volume mounts overlap with values for var.datadog_shared_volume. This module will remove the following containers' volume_mounts sharing a name or path with the Datadog shared volume: ${join(",", [for vm in local.all_volume_mounts : format("\n%s:%s", vm.name, vm.mount_path) if !contains(local.filtered_volume_mounts, vm)])}.\nThis module will add the Datadog volume_mount instead to all containers."
  }
}

check "function_target_is_provided" {
  assert {
    condition     = var.build_config != null ? var.build_config.function_target != null : true
    error_message = "The var.build_config.function_target attribute is required for instrumenting Cloud Run Functions."
  }
}

check "ready_port_is_not_already_in_use" {
  assert {
    # Containers in an instance share a network namespace, so the readiness port must not
    # be claimed by the agent sidecar or by an app container.
    condition = local.apm_enabled ? !contains(
      concat(
        [var.datadog_sidecar.health_port],
        [
          for c in local.containers_without_sidecar : c.ports.container_port
          if try(c.ports.container_port, null) != null
        ],
      ),
      var.datadog_apm_instrumentation.ready_port,
    ) : true
    error_message = "datadog_apm_instrumentation.ready_port (${try(var.datadog_apm_instrumentation.ready_port, "null")}) is already used by datadog_sidecar.health_port or a template.containers port. All containers in a Cloud Run instance share one network namespace, so the tracer readiness signal needs a port of its own."
  }
}

# Implementation
locals {
  labels = merge(
    var.labels,
    { service = local.datadog_service, dd_sls_terraform_module = local.module_version },
    var.datadog_env != null ? { env = var.datadog_env } : {},
    var.datadog_version != null ? { version = var.datadog_version } : {},
  )

  # Update the environments on the containers
  template_containers = concat(
    [for container in local.containers_without_sidecar :
      merge(
        container,
        {
          env = concat(
            # First, preserve user-defined env vars with value_source
            [for env in coalesce(container.env, []) : { name = env.name, value = env.value, value_source = env.value_source }
            if env.value_source != null && !contains(local.module_controlled_env_vars, env.name)],
            # Then add module-managed env vars
            [for name, value in merge(
              # variables which can be overrided by user provided configuration
              local.shared_env_vars,
              { DD_LOGS_INJECTION = "true" },
              # user provided env vars (without value_source) converted to map
              { for env in coalesce(container.env, []) : env.name => env.value if env.value_source == null },
              # always override user configuration with these env vars
              { DD_SERVERLESS_LOG_PATH = var.datadog_logging_path },
              # Single-Language SSI native env vars (language-specific tracer loading)
              local.apm_language_env_vars,
            ) : { name = name, value = value, value_source = null }]
          )
          # User-check 3: check for each provided container the volume mounts and if logging is enabled and the shared volume is an input, do not mount it again
          volume_mounts = concat(
            var.datadog_enable_logging ? [var.datadog_shared_volume] : [],
            local.apm_enabled ? [{
              name       = local.tracer_volume_name
              mount_path = local.tracer_volume_mount_path
            }] : [],
            [for vm in coalesce(container.volume_mounts, []) : vm if contains(local.filtered_volume_mounts, vm)],
          )
          # When SSI is enabled, Cloud Run start ordering holds the container until the
          # readiness startup probe passes, so the image entrypoint is left untouched.
          depends_on = local.apm_enabled ? distinct(concat(
            coalesce(container.depends_on, []),
            [local.tracer_sidecar_name],
          )) : container.depends_on
        },
    )],
    # We add the sidecar at the end due to an issue where cloud sql mounts are always
    # assigned to the first container (assuming it is the main app), so we should preserve
    # that ordering here to ensure that cloud sql mounts aren't added to the sidecar
    concat(
      local.tracer_sidecar != null ? [local.tracer_sidecar] : [],
      [local.sidecar_container],
    ),
  )

  # If dd_enable_logging is true, or datadog_apm_instrumentation is enabled add the shared volumes to the template volumes
  tracer_volume = local.apm_enabled ? [{
    name = local.tracer_volume_name
    empty_dir = {
      medium = var.datadog_apm_instrumentation.volume_medium
      # Disk-backed emptyDir requires at least 10Gi size_limit
      size_limit = local.using_disk_medium ? "10Gi" : "500Mi"
    }
  }] : []

  logger_volume = var.datadog_enable_logging ? [{
    name = var.datadog_shared_volume.name
    empty_dir = {
      medium     = "MEMORY"
      size_limit = var.datadog_shared_volume.size_limit
    }
  }] : []

  template_volumes = concat(local.volumes_without_shared_volume, local.tracer_volume, local.logger_volume)

  # emptyDir medium=DISK is a Cloud Run BETA feature; force at least BETA when SSI is on.
  # Preserve ALPHA if the caller already opted into it.
  launch_stage = local.using_disk_medium ? (
    var.launch_stage == "ALPHA" ? "ALPHA" : "BETA"
  ) : var.launch_stage

  # With a 10Gi DISK emptyDir, default project ephemeral-disk quota (~100Gi) allows
  # at most 10 instances. Cap (or default) max_instance_count accordingly when SSI is on.
  scaling = local.using_disk_medium ? {
    scaling_mode          = try(var.scaling.scaling_mode, null)
    min_instance_count    = try(var.scaling.min_instance_count, null)
    manual_instance_count = try(var.scaling.manual_instance_count, null)
    max_instance_count    = min(coalesce(try(var.scaling.max_instance_count, null), 10), 10)
  } : var.scaling
}


output "ignored_volume_mounts" {
  description = "List of volume mounts that overlap with the Datadog shared volume and are ignored by the module."
  value       = [for vm in local.all_volume_mounts : vm if !contains(local.filtered_volume_mounts, vm)]
}

output "ignored_containers" {
  description = "List of containers that are ignored by the module."
  value       = [for c in coalesce(var.template.containers, []) : c if !contains(local.containers_without_sidecar, c)]
}

output "ignored_volumes" {
  description = "List of volumes that are ignored by the module."
  value       = [for v in coalesce(var.template.volumes, []) : v if !contains(local.volumes_without_shared_volume, v)]
}
