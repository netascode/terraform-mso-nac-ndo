locals {
  fabric_template_ids = { for template in try(jsondecode(data.mso_rest.templates.content), []) : template.templateName => { "id" : template.templateId } if template.templateType == "fabricPolicy" }
}

locals {
  fabric_templates_sites = flatten(distinct([
    for template in local.fabric_templates : [
      for site in try(template.sites, []) : {
        key           = "${template.name}/${site}"
        template_name = template.name
        site_name     = site
      }
    ]
  ]))
}

data "mso_site" "fabric_templates_site" {
  for_each = toset(distinct([for site in local.fabric_templates_sites : site.site_name if(!var.manage_sites || local.ndo_platform_version == "4.1") && var.manage_fabric_templates]))
  name     = each.value
}

locals {
  fabric_policies = flatten([
    for template in local.fabric_templates : [{
      name  = template.name
      sites = [for site in try(template.sites, []) : var.manage_sites && local.ndo_platform_version != "4.1" ? mso_site.site[site].id : data.mso_site.fabric_templates_site[site].id]
    }]
  ])
}

resource "mso_template" "fabric_template" {
  for_each      = { for template in local.fabric_policies : template.name => template }
  template_name = each.value.name
  template_type = "fabric_policy"
  sites         = each.value.sites
}

locals {
  fabric_vlan_pools = flatten([
    for template in local.fabric_templates : [
      for pool in try(template.vlan_pools, []) : {
        key           = "${template.name}/${pool.name}"
        name          = pool.name
        template_name = template.name
        description   = try(pool.description, null)
        ranges = [for range in try(pool.ranges, []) : {
          from = range.from
          to   = range.to
        }]
      }
    ]
  ])
}

resource "mso_fabric_policies_vlan_pool" "fabric_policies_vlan_pool" {
  for_each    = { for pool in local.fabric_vlan_pools : pool.key => pool }
  template_id = mso_template.fabric_template[each.value.template_name].id
  name        = each.value.name
  description = each.value.description

  dynamic "vlan_range" {
    for_each = each.value.ranges
    content {
      from = vlan_range.value.from
      to   = vlan_range.value.to
    }
  }
}

locals {
  fabric_physical_domains = flatten([
    for template in local.fabric_templates : [
      for domain in try(template.physical_domains, []) : {
        key           = "${template.name}/${domain.name}"
        name          = domain.name
        template_name = template.name
        description   = try(domain.description, null)
        vlan_pool     = "${template.name}/${domain.vlan_pool}"
      }
    ]
  ])
}

resource "mso_fabric_policies_physical_domain" "fabric_policies_physical_domain" {
  for_each       = { for domain in local.fabric_physical_domains : domain.key => domain }
  template_id    = mso_template.fabric_template[each.value.template_name].id
  name           = each.value.name
  description    = each.value.description
  vlan_pool_uuid = mso_fabric_policies_vlan_pool.fabric_policies_vlan_pool[each.value.vlan_pool].uuid

  depends_on = [mso_fabric_policies_vlan_pool.fabric_policies_vlan_pool]
}

locals {
  fabric_l3_domains = flatten([
    for template in local.fabric_templates : [
      for domain in try(template.l3_domains, []) : {
        key           = "${template.name}/${domain.name}"
        name          = domain.name
        template_name = template.name
        description   = try(domain.description, null)
        vlan_pool     = "${template.name}/${domain.vlan_pool}"
      }
    ]
  ])
}

resource "mso_fabric_policies_l3_domain" "fabric_policies_l3_domain" {
  for_each       = { for domain in local.fabric_l3_domains : domain.key => domain }
  template_id    = mso_template.fabric_template[each.value.template_name].id
  name           = each.value.name
  description    = each.value.description
  vlan_pool_uuid = mso_fabric_policies_vlan_pool.fabric_policies_vlan_pool[each.value.vlan_pool].uuid

  depends_on = [mso_fabric_policies_vlan_pool.fabric_policies_vlan_pool]
}

locals {
  fabric_mcp_global_policies = flatten([
    for template in local.fabric_templates : [{
      key                               = template.name
      template_name                     = template.name
      name                              = try(template.mcp_global_policy.name, null)
      description                       = try(template.mcp_global_policy.description, null)
      admin_state                       = try(template.mcp_global_policy.admin_state, local.defaults.ndo.fabric_templates.fabric_policies.mcp_global_policy.admin_state) ? "enabled" : "disabled"
      enable_mcp_pdu_per_vlan           = try(template.mcp_global_policy.enable_mcp_pdu_per_vlan, local.defaults.ndo.fabric_templates.fabric_policies.mcp_global_policy.enable_mcp_pdu_per_vlan) ? "enabled" : "disabled"
      key_value                         = try(template.mcp_global_policy.key, null)
      loop_detect_multiplication_factor = try(template.mcp_global_policy.loop_detection, local.defaults.ndo.fabric_templates.fabric_policies.mcp_global_policy.loop_detection)
      port_disable_protection           = try(template.mcp_global_policy.port_disable_protection, local.defaults.ndo.fabric_templates.fabric_policies.mcp_global_policy.port_disable_protection) ? "enabled" : "disabled"
      initial_delay_time                = try(template.mcp_global_policy.initial_delay, local.defaults.ndo.fabric_templates.fabric_policies.mcp_global_policy.initial_delay)
      transmission_frequency_sec        = try(template.mcp_global_policy.transmission_frequency_sec, local.defaults.ndo.fabric_templates.fabric_policies.mcp_global_policy.transmission_frequency_sec)
      transmission_frequency_msec       = try(template.mcp_global_policy.transmission_frequency_msec, local.defaults.ndo.fabric_templates.fabric_policies.mcp_global_policy.transmission_frequency_msec)
    }] if try(template.mcp_global_policy, null) != null
  ])
}

resource "mso_fabric_policies_mcp_global_policy" "fabric_policies_mcp_global_policy" {
  for_each                          = { for policy in local.fabric_mcp_global_policies : policy.key => policy }
  template_id                       = mso_template.fabric_template[each.value.template_name].id
  name                              = each.value.name
  description                       = each.value.description
  admin_state                       = each.value.admin_state
  enable_mcp_pdu_per_vlan           = each.value.enable_mcp_pdu_per_vlan
  key                               = each.value.key_value
  loop_detect_multiplication_factor = each.value.loop_detect_multiplication_factor
  port_disable_protection           = each.value.port_disable_protection
  initial_delay_time                = each.value.initial_delay_time
  transmission_frequency_sec        = each.value.transmission_frequency_sec
  transmission_frequency_msec       = each.value.transmission_frequency_msec
}
