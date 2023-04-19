locals {
  ndo     = try(local.model.ndo, {})
  schemas = [for schema in try(local.ndo.schemas, []) : schema if var.manage_schemas && (length(var.managed_schemas) == 0 || contains(var.managed_schemas, schema.name))]
  tenants = [for tenant in try(local.ndo.tenants, []) : tenant if var.manage_tenants && (length(var.managed_tenants) == 0 || contains(var.managed_tenants, tenant.name))]
}
