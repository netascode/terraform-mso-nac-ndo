locals {
  tenant_users = flatten([
    for tenant in try(local.ndo.tenants, []) : [
      for user in try(tenant.users, []) : {
        key  = "${tenant.name}/${user.name}"
        name = user.name
      }
    ]
  ])
}

data "mso_user" "user" {
  for_each = { for user in local.tenant_users : user.key => user }
  username = each.value.name
}

resource "mso_tenant" "tenant" {
  for_each     = { for tenant in try(local.ndo.tenants, []) : tenant.name => tenant if var.manage_tenants }
  name         = each.value.name
  display_name = each.value.name
  description  = try(each.value.description, "")

  dynamic "user_associations" {
    for_each = { for user in try(each.value.users, []) : user.name => user }
    content {
      user_id = data.mso_user.user["${each.value.name}/${user_associations.value.name}"].id
    }
  }

  dynamic "site_associations" {
    for_each = { for site in try(each.value.sites, []) : site.name => site }
    content {
      site_id = mso_site.site[site_associations.value.name].id
    }
  }
}
