resource "mso_site" "site" {
  for_each     = { for site in try(local.ndo.sites, {}) : site.name => site if var.manage_sites && !contains(["4.1", "4.2", "4.3"], local.ndo_platform_version) }
  name         = each.value.name
  apic_site_id = each.value.id
  lifecycle {
    ignore_changes = [urls, username, location]
  }
}
