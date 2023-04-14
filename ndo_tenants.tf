locals {
  default_users = distinct([
    { name = "admin" },
    { name = var.mso_provider_username }
  ])
  tenant_users = flatten(distinct([
    for tenant in try(local.ndo.tenants, []) : [
      for user in distinct(concat(try(tenant.users, []), local.default_users)) : [user.name]
    ]
  ]))
}

data "mso_user" "user" {
  for_each = toset(local.tenant_users)
  username = each.value
}

resource "mso_tenant" "tenant" {
  for_each          = { for tenant in try(local.ndo.tenants, []) : tenant.name => tenant if var.manage_tenants }
  name              = each.value.name
  display_name      = each.value.name
  description       = try(each.value.description, "")
  orchestrator_only = try(each.value.orchestrator_only, local.defaults.ndo.tenants.orchestrator_only)

  dynamic "user_associations" {
    for_each = { for user in distinct(concat(try(each.value.users, []), local.default_users)) : user.name => user }
    content {
      user_id = data.mso_user.user[user_associations.value.name].id
    }
  }

  dynamic "site_associations" {
    for_each = { for site in try(each.value.sites, []) : site.name => site }
    content {
      site_id = mso_site.site[site_associations.value.name].id
    }
  }
}
