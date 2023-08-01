locals {
  default_users = distinct(concat([{ name = "admin" }], try(local.defaults.ndo.tenants.users, [])))
  tenant_users = flatten(distinct([
    for tenant in local.tenants : [
      for user in distinct(concat(try(tenant.users, []), local.default_users)) : user.name
    ]
  ]))
  tenant_sites = flatten(distinct([
    for tenant in local.tenants : [
      for site in try(tenant.sites, []) : site.name
    ]
  ]))
}

data "mso_user" "tenant_user" {
  for_each = toset(local.tenant_users)
  username = each.value
}

data "mso_site" "tenant_site" {
  for_each = !var.manage_sites ? toset(local.tenant_sites) : []
  name     = each.value
}

resource "mso_tenant" "tenant" {
  for_each          = { for tenant in local.tenants : tenant.name => tenant }
  name              = each.value.name
  display_name      = each.value.name
  description       = try(each.value.description, "")
  orchestrator_only = try(each.value.orchestrator_only, local.defaults.ndo.tenants.orchestrator_only)

  dynamic "user_associations" {
    for_each = { for user in distinct(concat(try(each.value.users, []), local.default_users)) : user.name => user }
    content {
      user_id = data.mso_user.tenant_user[user_associations.value.name].id
    }
  }

  dynamic "site_associations" {
    for_each = { for site in try(each.value.sites, []) : site.name => site }
    content {
      site_id               = var.manage_sites ? mso_site.site[site_associations.value.name].id : data.mso_site.tenant_site[site_associations.value.name].id
      vendor                = try(site_associations.value.azure_subscription_id, null) != null ? "azure" : null
      azure_subscription_id = try(site_associations.value.azure_subscription_id, null) != null ? site_associations.value.azure_subscription_id : null
      azure_access_type     = try(site_associations.value.azure_subscription_id, null) != null ? "managed" : null
    }
  }
}
