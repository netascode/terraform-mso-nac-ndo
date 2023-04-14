locals {
  ndo     = try(local.model.ndo, {})
  schemas = [for schema in try(local.ndo.schemas, []) : schema if var.manage_schemas && (length(var.managed_schemas) == 0 || contains(var.managed_schemas, schema.name))]
}
