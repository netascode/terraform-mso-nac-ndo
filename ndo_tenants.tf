locals {
  default_users = distinct(concat([{ name = "admin" }], try(local.defaults.ndo.tenants.users, [])))
  tenant_users = flatten(distinct([
    for tenant in local.tenants : [
      for user in distinct(concat(try(tenant.users, []), local.default_users)) : [user.name]
    ]
  ]))
}

data "mso_user" "user" {
  for_each = toset(local.tenant_users)
  username = each.value
}

resource "mso_tenant" "tenant" {
  for_each          = { for tenant in local.tenants : tenant.name => tenant if var.manage_tenants }
  name              = each.value.name
  display_name      = each.value.name
  description       = try(each.value.description, "")
  orchestrator_only = try(each.value.orchestrator_only, local.defaults.ndo.tenants.orchestrator_only, true) # not added to schema yet

  dynamic "user_associations" {
    for_each = { for user in distinct(concat(try(each.value.users, []), local.default_users)) : user.name => user }
    content {
      user_id = data.mso_user.user[user_associations.value.name].id
    }
  }

  dynamic "site_associations" {
    for_each = { for site in try(each.value.sites, []) : site.name => site }
    content {
      site_id = var.manage_sites ? mso_site.site[site_associations.value.name].id : data.mso_site.site[site_associations.value.name].id
    }
  }
}

data "mso_tenant" "tenant" {
  for_each     = { for tenant in try(local.ndo.tenants, []) : tenant.name => tenant if !var.manage_tenants || (length(var.managed_tenants) != 0 && !contains(var.managed_tenants, tenant.name)) }
  name         = each.value.name
  display_name = each.value.name
}
