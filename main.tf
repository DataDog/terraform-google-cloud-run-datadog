
locals {
  datadog_service = var.datadog_service != null ? var.datadog_service : var.name
  datadog_logging_vol = { #the shared volume for logging which each container can write their Datadog logs to
    name = var.datadog_shared_volume.name
    empty_dir = {
      medium = "MEMORY"
    }
  }
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
    "DD_LOGS_INJECTION", # this is not an env var needed on the sidecar anyways
  ]


  ### Variables to handle input checks and infrastructure overrides (volume, volume_mount, sidecar container)
  # User-check 1: use this to override user's var.template.volumes and remove the shared volume if shared_volume already exists and logging is enabled, else keep user's volumes
  volumes_without_shared_volume = var.datadog_enable_logging == true ? [
    for v in coalesce(var.template.volumes, []) : v
    if v.name != var.datadog_shared_volume.name
  ] : coalesce(var.template.volumes, [])

  # flag if logging is enabled and shared_volume is already in the template volumes (name of volume exists)
  shared_volume_already_exists = length(coalesce(var.template.volumes, [])) != length(local.volumes_without_shared_volume)

  # User-check 2: check if sidecar container already exists and remove it from the var.template.containers list if it does (to be overridden by module's instantiation)
  containers_without_sidecar = [
    for c in coalesce(var.template.containers, []) : c
    if c.name != var.datadog_sidecar.name
  ]

  # flag if sidecar container already exists
  already_has_sidecar = length(coalesce(var.template.containers, [])) != length(local.containers_without_sidecar)

  # User-check 3: check for each provided container (ignoring sidecar if provided) the volume mounts and if logging is enabled, exclude all volume mounts with same name OR path as the shared volume
  all_volume_mounts = flatten([
    for c in coalesce(local.containers_without_sidecar, []) :
    coalesce(c.volume_mounts, [])
  ])

  #filter out volume mounts with same name or path as the shared volume only if logging is enabled
  filtered_volume_mounts = var.datadog_enable_logging == true ? [
    for vm in coalesce(local.all_volume_mounts, []) :
    vm if !(vm.name == var.datadog_shared_volume.name || vm.mount_path == var.datadog_shared_volume.mount_path)
  ] : local.all_volume_mounts

  overlapping_volume_mounts = length(local.filtered_volume_mounts) != length(local.all_volume_mounts)

  # User-check 4: merge env vars for sidecar-instrumentation with user-provided env vars for agent-configuration
  # (ignore any module-controlled env vars that user provides in var.datadog_sidecar.env_vars)
  required_module_sidecar_env_vars = [
    {
      env_name  = "DD_API_KEY"
      env_value = var.datadog_api_key
    },
    {
      env_name  = "DD_SITE"
      env_value = var.datadog_site
    },
    {
      env_name  = "DD_SERVICE"
      env_value = local.datadog_service
    },
    {
      env_name  = "DD_HEALTH_PORT"
      env_value = tostring(var.datadog_sidecar.health_port)
    },
  ]
  all_module_sidecar_env_vars = concat(
    local.required_module_sidecar_env_vars,
    var.datadog_version != null ? [{
      env_name  = "DD_VERSION"
      env_value = var.datadog_version
    }] : [],
    var.datadog_env != null ? [{
      env_name  = "DD_ENV"
      env_value = var.datadog_env
    }] : [],
    var.datadog_tags != null ? [
      {
        env_name  = "DD_TAGS"
        env_value = join(",", var.datadog_tags)
      }
    ] : [],
    var.datadog_log_level != null ? [{
      env_name  = "DD_LOG_LEVEL"
      env_value = var.datadog_log_level
    }] : [],
    var.datadog_enable_logging == true ? [{
      env_name  = "DD_SERVERLESS_LOG_PATH"
      env_value = var.datadog_logging_path
    }] : [],
  )
  agent_env_vars = [ # user-provided env vars for agent-configuration, filter out the ones that are module-controlled
    for env in coalesce(var.datadog_sidecar.env_vars, []) : {
      env_name  = env.name
      env_value = env.value
    }
    if !contains(local.module_controlled_env_vars, env.name)
  ]
  all_sidecar_env_vars = concat(
    local.agent_env_vars,
    local.all_module_sidecar_env_vars
  )

}

check "logging_volume_already_exists" {
  assert {
    condition     = local.shared_volume_already_exists == false
    error_message = "Datadog log collection is enabled and a volume with the name \"${var.datadog_shared_volume.name}\" already exists in the var.template.volumes list. This module will override the existing volume with the settings provided in var.datadog_shared_volume and use it for Datadog log collection. To disable log collection, set var.datadog_enable_logging to false."
  }
}

check "sidecar_already_exists" {
  assert {
    condition     = local.already_has_sidecar == false
    error_message = "A sidecar container with the name \"${var.datadog_sidecar.name}\" already exists in the var.template.containers list. This module will override the existing container(s) with the settings provided in var.datadog_sidecar."
  }
}

check "volume_mounts_share_names_and_or_paths" {
  assert {
    condition     = local.overlapping_volume_mounts == false
    error_message = "Logging is enabled, and user-inputted volume mounts overlap with values for var.datadog_shared_volume. This module will remove the following containers' volume_mounts sharing a name or path with the Datadog shared volume: ${join(",", [for vm in local.all_volume_mounts : format("\n%s:%s", vm.name, vm.mount_path) if !contains(local.filtered_volume_mounts, vm)])}.\nThis module will add the Datadog volume_mount instead to all containers."
  }
}
