# Unless explicitly stated otherwise all files in this repository are licensed under the Apache-2.0 License.
# This product includes software developed at Datadog (https://www.datadoghq.com/) Copyright 2025 Datadog, Inc.

# tracer sidecar, main-container selection,
# and the loader env vars merged onto the instrumented container.
locals {
  apm_enabled        = var.datadog_apm_instrumentation != null
  injection_mode_tag = "_dd.injection.mode:serverless-single-lang"
  # Tracer copy volume mount path used by dd-lib-*-init and language env vars.
  tracer_volume_name       = "datadog-tracer"
  tracer_volume_mount_path = "/datadog-lib"
  tracer_sidecar_name      = "datadog-tracer"
  tracer_libc              = local.apm_enabled ? var.datadog_apm_instrumentation.tracer_libc : null
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

  # SSI toggles owned on the main container. Loader vars are fragment-merged, not replaced.
  apm_module_controlled_env_vars = local.apm_enabled ? ["DD_TRACE_ENABLED"] : []

  # instrument exactly one main app container.
  # Prefer the sole port-bearing candidate; if none declare ports, allow a single candidate;
  # otherwise the layout is ambiguous and rejected (enforced by check blocks when SSI is enabled).
  apm_containers_with_ports = [
    for c in local.containers_without_sidecar : c
    if try(c.ports, null) != null
  ]
  # A ports block without a container_port still exposes a port: Cloud Run listens on 8080.
  cloud_run_default_container_port = 8080
  apm_app_container_ports = [
    for c in local.apm_containers_with_ports :
    coalesce(try(c.ports.container_port, null), local.cloud_run_default_container_port)
  ]
  # Ports already claimed inside the instance's shared network namespace.
  apm_reserved_ports = concat(
    [var.datadog_sidecar.health_port],
    local.apm_app_container_ports,
  )
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
  # Index the module instruments; null when SSI is disabled so no container matches it.
  apm_main_container_index = local.apm_enabled ? local.main_container_index : null

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

  tracer_volume = local.apm_enabled ? [{
    name = local.tracer_volume_name
    empty_dir = {
      medium     = "MEMORY"
      size_limit = "500Mi"
    }
  }] : []

  # Resource-level marker datadog-ci uses to recognize SSI-managed services, applied in local.labels
  apm_labels = local.apm_enabled ? { dd_sls_injection_mode = "single_language" } : {}

  ### Contributions to the main app container, applied in local.template_containers

  # Env vars the module owns on the instrumented container. Loader vars are listed here so a
  # secret-backed value is not carried through: they cannot be fragment-merged (rejected by check).
  apm_main_container_managed_env_names = concat(
    local.apm_module_controlled_env_vars,
    local.apm_loader_env_names,
  )
  apm_main_container_env = local.apm_enabled ? merge(
    {
      DD_TRACE_ENABLED = "true"
      DD_TAGS          = local.apm_main_container_dd_tags
    },
    local.apm_merged_loader_env,
  ) : {}
  # The app waits on both sidecars: the tracer copy must finish and the agent must be ready
  # before the app starts, so no initial telemetry is lost.
  apm_main_container_depends_on = local.apm_enabled ? [
    local.tracer_sidecar_name,
    var.datadog_sidecar.name,
  ] : []
}

check "ready_port_is_not_already_in_use" {
  assert {
    # Containers in an instance share a network namespace, so the readiness port must not
    # be claimed by the agent sidecar or by an app container.
    condition     = !local.apm_enabled || !contains(local.apm_reserved_ports, var.datadog_apm_instrumentation.ready_port)
    error_message = "datadog_apm_instrumentation.ready_port (${try(var.datadog_apm_instrumentation.ready_port, "null")}) is already used by datadog_sidecar.health_port or a template.containers port (a ports block without a container_port listens on ${local.cloud_run_default_container_port}). All containers in a Cloud Run instance share one network namespace, so the tracer readiness signal needs a port of its own."
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
