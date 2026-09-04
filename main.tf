locals {
  ndo                       = try(local.model.ndo, {})
  schemas                   = [for schema in try(local.ndo.schemas, []) : schema if var.manage_schemas && (length(var.managed_schemas) == 0 || contains(var.managed_schemas, schema.name))]
  tenants                   = [for tenant in try(local.ndo.tenants, []) : tenant if var.manage_tenants && (length(var.managed_tenants) == 0 || contains(var.managed_tenants, tenant.name))]
  ndo_version_full          = jsondecode(data.mso_rest.ndo_version.content).version
  ndo_platform_version_full = jsondecode(data.mso_rest.ndo_version.content).platformVersion
  ndo_version               = regex("^[0-9]+[.][0-9]+", local.ndo_version_full)
  ndo_platform_version      = regex("^[0-9]+[.][0-9]+", local.ndo_platform_version_full)
  # NDO hosted on Nexus Dashboard 4.1 or later, where ND owns values the data
  # model used to drive (site id / apicSiteId, remote locations). platformVersion
  # is the ND version, on a different scale from the NDO application version: a
  # standalone NDO 4.4 reports ND 3.2, so a >= 4.1 test separates the two
  # flavors and keeps working for ND releases after 4.3.
  nd_managed               = tonumber(local.ndo_platform_version) >= 4.1
  tenant_templates         = [for template in try(local.ndo.tenant_templates.tenant_policies, []) : template if var.manage_tenant_templates && (length(var.managed_tenant_templates) == 0 || contains(var.managed_tenant_templates, template.name))]
  fabric_templates         = [for template in try(local.ndo.fabric_templates.fabric_policies, []) : template if var.manage_fabric_templates && (length(var.managed_fabric_templates) == 0 || contains(var.managed_fabric_templates, template.name))]
  service_device_templates = [for template in try(local.ndo.tenant_templates.service_devices, []) : template if var.manage_tenant_templates]
}

data "mso_rest" "ndo_version" {
  path = "api/v1/platform/version"
}
