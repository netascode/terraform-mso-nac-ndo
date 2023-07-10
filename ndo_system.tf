locals {
  # tflint-ignore: terraform_unused_declarations
  system_config = [{
    op   = "replace"
    path = "/bannerConfig"
    value = [{
      alias = try(local.ndo.system_config.banner.alias, "")
      banner = {
        bannerType  = try(local.ndo.system_config.banner.type, local.defaults.ndo.system_config.banner.type)
        message     = try(local.ndo.system_config.banner.type, "")
        bannerState = try(local.ndo.system_config.banner.state, local.defaults.ndo.system_config.banner.state)
      }
    }]
  }]
}

data "mso_rest" "system_config" {
  count = var.manage_system ? 1 : 0
  path  = "api/v1/platform/systemConfig"
}

resource "mso_rest" "system_config" {
  count   = var.manage_system ? 1 : 0
  path    = "api/v1/platform/systemConfig/${jsondecode(data.mso_rest.system_config[0].content).systemConfigs.id}"
  method  = "PATCH"
  payload = jsonencode(local.system_config)
}

resource "mso_remote_location" "remote_location" {
  for_each    = { for rl in try(local.ndo.remote_locations, []) : rl.name => rl }
  name        = each.value.name
  description = try(each.value.description, "")
  protocol    = try(each.value.protocol, local.defaults.ndo.remote_locations.protocol)
  hostname    = each.value.hostname_ip
  port        = try(each.value.port, local.defaults.ndo.remote_locations.port)
  path        = try(each.value.path, local.defaults.ndo.remote_locations.path)
  username    = try(each.value.username, null)
  password    = try(each.value.password, null)
  ssh_key     = try(each.value.ssh_key, null)
  passphrase  = try(each.value.passphrase, null)
}
