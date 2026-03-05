locals {
  ndo              = try(local.model.ndo, {})
  schemas          = [for schema in try(local.ndo.schemas, []) : schema if var.manage_schemas && (length(var.managed_schemas) == 0 || contains(var.managed_schemas, schema.name))]
  tenants          = [for tenant in try(local.ndo.tenants, []) : tenant if var.manage_tenants && (length(var.managed_tenants) == 0 || contains(var.managed_tenants, tenant.name))]
  ndo_version_full = jsondecode(data.mso_rest.ndo_version.content).version
  ndo_version      = regex("^[0-9]+[.][0-9]+", local.ndo_version_full)
  tenant_templates = [for template in try(local.ndo.tenant_templates.tenant_policies, []) : template if var.manage_tenant_templates && (length(var.managed_tenant_templates) == 0 || contains(var.managed_tenant_templates, template.name))]
}

data "mso_rest" "ndo_version" {
  path = "api/v1/platform/version"
}
