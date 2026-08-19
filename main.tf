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
  tracer_libc = local.apm_enabled ? var.datadog_apm_instrumentation.tracer_libc : null
  # PHP loader layout differs by libc ABI (linux-gnu vs linux-musl).
  php_loader_dir = local.apm_enabled ? (
    "${local.tracer_volume_mount_path}/${local.tracer_libc == "musl" ? "linux-musl" : "linux-gnu"}/loader"
  ) : null

  tracer_ready_probe = local.apm_enabled ? {
    tcp_socket            = { port = var.datadog_apm_instrumentation.ready_port }
    initial_delay_seconds = 0
    period_seconds        = 5
    timeout_seconds       = 1
    failure_threshold     = 48
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

  # Fragment-aware SSI loader env.
  # mode: append | prepend | set-if-absent
  # separator: entry boundary for append/prepend (null = whole-string position match)
  # preserve_leading_empty: keep a leading separator when the var was unset (PHP_INI_SCAN_DIR)
  apm_env_fragments_by_language = {
    java = [
      {
        name                   = "JAVA_TOOL_OPTIONS"
        value                  = "-javaagent:${local.tracer_volume_mount_path}/dd-java-agent.jar -XX:+IgnoreUnrecognizedVMOptions"
        mode                   = "append"
        separator              = " "
        preserve_leading_empty = false
        max_length             = null
      },
    ]
    js = [
      {
        name                   = "NODE_OPTIONS"
        value                  = "--require ${local.tracer_volume_mount_path}/node_modules/dd-trace/init.js"
        mode                   = "append"
        separator              = " "
        preserve_leading_empty = false
        max_length             = null
      },
    ]
    python = [
      {
        name                   = "PYTHONPATH"
        value                  = local.tracer_volume_mount_path
        mode                   = "append"
        separator              = ":"
        preserve_leading_empty = false
        max_length             = null
      },
    ]
    dotnet = [
      {
        name                   = "CORECLR_ENABLE_PROFILING"
        value                  = "1"
        mode                   = "set-if-absent"
        separator              = null
        preserve_leading_empty = false
        max_length             = null
      },
      {
        name                   = "CORECLR_PROFILER"
        value                  = "{846F5F1C-F9AE-4B07-969E-05C26BC060D8}"
        mode                   = "set-if-absent"
        separator              = null
        preserve_leading_empty = false
        max_length             = null
      },
      {
        name                   = "CORECLR_PROFILER_PATH"
        value                  = "${local.tracer_volume_mount_path}/Datadog.Trace.ClrProfiler.Native.so"
        mode                   = "set-if-absent"
        separator              = null
        preserve_leading_empty = false
        max_length             = null
      },
      {
        name                   = "DD_DOTNET_TRACER_HOME"
        value                  = local.tracer_volume_mount_path
        mode                   = "set-if-absent"
        separator              = null
        preserve_leading_empty = false
        max_length             = null
      },
      {
        name                   = "LD_PRELOAD"
        value                  = "${local.tracer_volume_mount_path}/continuousprofiler/Datadog.Linux.ApiWrapper.x64.so"
        mode                   = "prepend"
        separator              = " "
        preserve_leading_empty = false
        max_length             = 1024
      },
    ]
    ruby = [
      {
        name                   = "RUBYOPT"
        value                  = "-r${local.tracer_volume_mount_path}/auto_inject"
        mode                   = "prepend"
        separator              = " "
        preserve_leading_empty = false
        max_length             = null
      },
    ]
    php = [
      {
        name                   = "PHP_INI_SCAN_DIR"
        value                  = local.php_loader_dir
        mode                   = "append"
        separator              = ":"
        preserve_leading_empty = true
        max_length             = null
      },
      {
        name                   = "DD_LOADER_PACKAGE_PATH"
        value                  = local.tracer_volume_mount_path
        mode                   = "set-if-absent"
        separator              = null
        preserve_leading_empty = false
        max_length             = null
      },
    ]
  }

  apm_env_fragments    = local.apm_enabled ? local.apm_env_fragments_by_language[var.datadog_apm_instrumentation.language] : []
  apm_loader_env_names = [for fragment in local.apm_env_fragments : fragment.name]

  # Base env vars the module always owns on every app container
  module_controlled_env_vars = [
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
  ]
  # SSI toggles owned on the main container. Loader vars are fragment-merged, not replaced.
  apm_module_controlled_env_vars = local.apm_enabled ? ["DD_TRACE_ENABLED"] : []


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

  # instrument exactly one main app container.
  # Prefer the sole port-bearing candidate; if none declare ports, allow a single candidate;
  # otherwise the layout is ambiguous and rejected (enforced by check blocks when SSI is enabled).
  apm_containers_with_ports = [
    for c in local.containers_without_sidecar : c
    if try(c.ports, null) != null
  ]
  main_container_indexes = [
    for idx, c in local.containers_without_sidecar : idx
    if(
      length(local.apm_containers_with_ports) == 1
      ? try(c.ports, null) != null
      : length(local.apm_containers_with_ports) == 0 && length(local.containers_without_sidecar) == 1
    )
  ]
  main_container_index = length(local.main_container_indexes) == 1 ? local.main_container_indexes[0] : null
  main_container       = local.main_container_index != null ? local.containers_without_sidecar[local.main_container_index] : null

  # Literal (non-secret) env on the main container — the base for fragment-aware SSI merges.
  main_container_literal_env = local.main_container == null ? tomap({}) : tomap({
    for env in coalesce(local.main_container.env, []) : env.name => env.value
    if env.value_source == null && env.value != null
  })

  apm_existing_loader_env_value = {
    for fragment in local.apm_env_fragments :
    fragment.name => lookup(local.main_container_literal_env, fragment.name, "")
  }

  # Whether the existing value already carries this fragment, making the merge a no-op
  apm_loader_fragment_present = {
    for fragment in local.apm_env_fragments : fragment.name => (
      local.apm_existing_loader_env_value[fragment.name] == "" ? false : (
        fragment.separator != null
        ? strcontains(
          "${fragment.separator}${local.apm_existing_loader_env_value[fragment.name]}${fragment.separator}",
          "${fragment.separator}${fragment.value}${fragment.separator}",
        )
        : (
          fragment.mode == "append"
          ? endswith(local.apm_existing_loader_env_value[fragment.name], fragment.value)
          : startswith(local.apm_existing_loader_env_value[fragment.name], fragment.value)
        )
      )
    )
  }

  # Merge each loader fragment into the existing main-container value
  apm_merged_loader_env = {
    for fragment in local.apm_env_fragments : fragment.name => (
      fragment.mode == "set-if-absent" ? (
        local.apm_existing_loader_env_value[fragment.name] != ""
        ? local.apm_existing_loader_env_value[fragment.name]
        : fragment.value
        ) : (
        # append / prepend. Existing fragments are left where they are
        local.apm_loader_fragment_present[fragment.name]
        ? local.apm_existing_loader_env_value[fragment.name]
        : (
          local.apm_existing_loader_env_value[fragment.name] == ""
          ? (fragment.preserve_leading_empty ? "${fragment.separator}${fragment.value}" : fragment.value)
          : (
            fragment.mode == "append"
            ? "${local.apm_existing_loader_env_value[fragment.name]}${fragment.separator}${fragment.value}"
            : "${fragment.value}${fragment.separator}${local.apm_existing_loader_env_value[fragment.name]}"
          )
        )
      )
    )
  }

  apm_loader_secret_env_names = local.main_container == null ? [] : [
    for env in coalesce(local.main_container.env, []) : env.name
    if env.value_source != null && contains(local.apm_loader_env_names, env.name)
  ]
  apm_loader_duplicate_env_names = local.main_container == null ? [] : distinct([
    for fragment in local.apm_env_fragments : fragment.name
    if length([for env in coalesce(local.main_container.env, []) : env if env.name == fragment.name]) > 1
  ])
  apm_loader_set_if_absent_conflicts = [
    for fragment in local.apm_env_fragments : fragment.name
    if fragment.mode == "set-if-absent"
    && local.apm_existing_loader_env_value[fragment.name] != ""
    && local.apm_existing_loader_env_value[fragment.name] != fragment.value
  ]
  apm_loader_env_exceeding_max_length = [
    for fragment in local.apm_env_fragments : fragment.name
    if fragment.max_length == null
    ? false
    : length(local.apm_merged_loader_env[fragment.name]) > fragment.max_length
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
  apm_main_container_base_tags = (
    lookup(local.main_container_literal_env, "DD_TAGS", null) != null
    ? local.main_container_literal_env["DD_TAGS"]
    : (var.datadog_tags != null ? join(",", var.datadog_tags) : "")
  )
  apm_main_container_dd_tags = local.apm_enabled ? join(",", concat(
    [local.injection_mode_tag],
    [
      for tag in split(",", local.apm_main_container_base_tags) : tag
      if tag != "" && tag != local.injection_mode_tag
    ],
  )) : null
  shared_env_vars = merge(
    { DD_SERVICE = local.datadog_service },
    var.datadog_version != null ? { DD_VERSION = var.datadog_version } : {},
    var.datadog_env != null ? { DD_ENV = var.datadog_env } : {},
    var.datadog_tags != null ? { DD_TAGS = join(",", var.datadog_tags) } : {},
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
  tracer_volume_mount = {
    name       = local.tracer_volume_name
    mount_path = local.tracer_volume_mount_path
  }

  tracer_sidecar = local.apm_enabled ? {
    image   = "gcr.io/datadoghq/dd-lib-${var.datadog_apm_instrumentation.language}-init:${var.datadog_apm_instrumentation.tracer_version}"
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

check "apm_main_container_exists" {
  assert {
    condition     = !local.apm_enabled || length(local.containers_without_sidecar) > 0
    error_message = "No application container was found to instrument. Add a container to template.containers (other than the Datadog agent sidecar)."
  }
}

check "apm_main_container_not_ambiguous" {
  assert {
    condition = !local.apm_enabled || local.main_container_index != null
    error_message = length(local.apm_containers_with_ports) > 1 ? (
      "Multiple containers declare ports, so the main container is ambiguous: ${join(", ", [for c in local.apm_containers_with_ports : coalesce(try(c.name, null), "<unnamed>")])}. Cloud Run allows exactly one main container."
      ) : (
      "No container declares ports, so the main container is ambiguous: ${join(", ", [for c in local.containers_without_sidecar : coalesce(try(c.name, null), "<unnamed>")])}. Declare a container port on your main container."
    )
  }
}

check "apm_loader_env_not_secret_backed" {
  assert {
    condition     = !local.apm_enabled || length(local.apm_loader_secret_env_names) == 0
    error_message = "SSI loader env var(s) on the main container are populated from a secret reference, which Datadog cannot safely extend: ${join(", ", local.apm_loader_secret_env_names)}. Set them to a literal value or remove them before enabling datadog_apm_instrumentation."
  }
}

check "apm_loader_env_not_duplicated" {
  assert {
    condition     = !local.apm_enabled || length(local.apm_loader_duplicate_env_names) == 0
    error_message = "SSI loader env var(s) appear more than once on the main container, so Datadog cannot safely modify them: ${join(", ", local.apm_loader_duplicate_env_names)}. Remove the duplicates before enabling datadog_apm_instrumentation."
  }
}

check "apm_loader_env_set_if_absent_compatible" {
  assert {
    condition     = !local.apm_enabled || length(local.apm_loader_set_if_absent_conflicts) == 0
    error_message = "SSI loader env var(s) on the main container conflict with required tracer values: ${join(", ", local.apm_loader_set_if_absent_conflicts)}. Remove or update them to match the Datadog tracer settings before enabling datadog_apm_instrumentation."
  }
}

check "apm_loader_env_within_max_length" {
  assert {
    condition     = !local.apm_enabled || length(local.apm_loader_env_exceeding_max_length) == 0
    error_message = "SSI loader env var(s) exceed their max length after merging the tracer fragment: ${join(", ", local.apm_loader_env_exceeding_max_length)}. Shorten the existing value before enabling datadog_apm_instrumentation."
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
    [for idx, container in local.containers_without_sidecar :
      merge(
        container,
        {
          env = concat(
            # First, preserve user-defined env vars with value_source
            [for env in coalesce(container.env, []) : { name = env.name, value = env.value, value_source = env.value_source }
              if env.value_source != null && !contains(
                concat(
                  local.module_controlled_env_vars,
                  local.apm_enabled && idx == local.main_container_index ? local.apm_module_controlled_env_vars : [],
                  # Loader vars with value_source cannot be fragment-merged; rejected by check.
                  local.apm_enabled && idx == local.main_container_index ? local.apm_loader_env_names : [],
                ),
                env.name,
            )],
            # Then add module-managed env vars
            [for name, value in merge(
              # variables which can be overrided by user provided configuration
              local.shared_env_vars,
              { DD_LOGS_INJECTION = "true" },
              # user provided env vars (without value_source) converted to map
              { for env in coalesce(container.env, []) : env.name => env.value if env.value_source == null },
              # always override user configuration with these env vars
              { DD_SERVERLESS_LOG_PATH = var.datadog_logging_path },
              # SSI: enable tracing, tag the injection mode, and fragment-merge loader env vars
              # only on the main container
              local.apm_enabled && idx == local.main_container_index ? merge(
                {
                  DD_TRACE_ENABLED = "true"
                  DD_TAGS          = local.apm_main_container_dd_tags
                },
                local.apm_merged_loader_env,
              ) : {},
            ) : { name = name, value = value, value_source = null }]
          )
          # User-check 3: check for each provided container the volume mounts and if logging is enabled and the shared volume is an input, do not mount it again
          volume_mounts = concat(
            var.datadog_enable_logging ? [var.datadog_shared_volume] : [],
            # Tracer volume is only needed on the container that loads the tracer.
            local.apm_enabled && idx == local.main_container_index ? [{
              name       = local.tracer_volume_name
              mount_path = local.tracer_volume_mount_path
            }] : [],
            [for vm in coalesce(container.volume_mounts, []) : vm if contains(local.filtered_volume_mounts, vm)],
          )
          # When SSI is enabled, Cloud Run start ordering holds the main container until the
          # readiness startup probe passes, so the image entrypoint is left untouched.
          depends_on = local.apm_enabled && idx == local.main_container_index ? distinct(concat(
            coalesce(container.depends_on, []),
            [local.tracer_sidecar_name, var.datadog_sidecar.name],
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
