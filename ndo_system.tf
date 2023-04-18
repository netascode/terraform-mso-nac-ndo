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

/* data "mso_rest" "system_config" {
  count = var.manage_system ? 1 : 0
  path  = "api/v1/platform/systemConfig"
}

resource "mso_rest" "system_config" {
  count   = var.manage_system ? 1 : 0
  path    = "api/v1/platform/systemConfig/${jsondecode(data.mso_rest.system_config[0].content).systemConfigs.id}"
  method  = "PATCH"
  payload = jsonencode(local.system_config)
} */
