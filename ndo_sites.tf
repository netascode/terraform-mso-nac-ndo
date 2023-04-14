resource "mso_site" "site" {
  for_each     = { for site in try(local.ndo.sites, {}) : site.name => site if var.manage_sites }
  name         = each.value.name
  apic_site_id = each.value.id
  lifecycle {
    ignore_changes = [urls, username, location]
  }
}
