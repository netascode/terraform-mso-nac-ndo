locals {
  tenant_templates_tenants = [
    for template in local.tenant_templates : template.tenant
  ]
}

data "mso_tenant" "tenant_templates_tenant" {
  for_each = toset([for tenant in distinct(local.tenant_templates_tenants) : tenant if !contains(local.managed_tenants, tenant) && var.manage_tenant_templates])
  name     = each.value
}

locals {
  tenant_templates_sites = flatten(distinct([
    for template in local.tenant_templates : [
      for site in try(template.sites, []) : {
        key           = "${template.name}/${site}"
        template_name = template.name
        site_name     = site
      }
    ]
  ]))
}

data "mso_site" "tenant_templates_site" {
  for_each = toset(distinct([for site in local.tenant_templates_sites : site.site_name if !var.manage_sites && var.manage_tenant_templates]))
  name     = each.value
}

locals {
  tenant_policies = flatten([
    for template in local.tenant_templates : [{
      name   = template.name
      tenant = contains(local.managed_tenants, template.tenant) ? mso_tenant.tenant[template.tenant].id : data.mso_tenant.tenant_templates_tenant[template.tenant].id
      sites  = [for site in try(template.sites, []) : data.mso_site.tenant_templates_site[site].id]
    }]
  ])
}

resource "mso_template" "tenant_template" {
  for_each      = { for template in local.tenant_policies : template.name => template }
  template_name = each.value.name
  template_type = "tenant"
  tenant_id     = each.value.tenant
  sites         = each.value.sites
}

locals {
  dhcp_provider_epgs = flatten([
    for template in local.tenant_templates : [
      for policy in try(template.dhcp_relay_policies, []) : [
        for provider in try(policy.providers, []) : {
          key                 = "${provider.schema}/${provider.template}/${provider.application_profile}/${provider.endpoint_group}"
          schema              = provider.schema
          template            = provider.template
          application_profile = try(provider.application_profile, null)
          endpoint_group      = try(provider.endpoint_group, null)
        } if provider.type == "epg"
      ]
    ]
  ])
  dhcp_provider_external_epgs = flatten([
    for template in local.tenant_templates : [
      for policy in try(template.dhcp_relay_policies, []) : [
        for provider in try(policy.providers, []) : {
          key                     = "${provider.schema}/${provider.template}/${provider.external_endpoint_group}"
          schema                  = provider.schema
          template                = provider.template
          external_endpoint_group = try(provider.external_endpoint_group, null)
        } if provider.type == "external_epg"
      ]
    ]
  ])
}

data "mso_schema_template_anp_epg" "schema_template_anp_epg" {
  for_each      = { for provider in distinct(local.dhcp_provider_epgs) : provider.key => provider if(!var.manage_schemas || (var.manage_schemas && !contains(local.managed_schemas, provider.schema))) }
  schema_id     = local.schema_ids[each.value.schema].id
  template_name = each.value.template
  anp_name      = each.value.application_profile
  name          = each.value.endpoint_group
}

data "mso_schema_template_external_epg" "schema_template_external_epg" {
  for_each          = { for provider in distinct(local.dhcp_provider_external_epgs) : provider.key => provider if(!var.manage_schemas || (var.manage_schemas && !contains(local.managed_schemas, provider.schema))) }
  schema_id         = local.schema_ids[each.value.schema].id
  template_name     = each.value.template
  external_epg_name = each.value.external_endpoint_group
}

locals {
  dhcp_relay_policies = flatten([
    for template in local.tenant_templates : [
      for policy in try(template.dhcp_relay_policies, []) : {
        name          = policy.name
        template_name = template.name
        description   = try(policy.description, null)
        providers = [for provider in try(policy.providers, []) : {
          key            = "${template.name}/${policy.name}/${provider.name}/${provider.type}"
          name           = provider.name
          type           = provider.type
          ip             = provider.ip
          use_server_vrf = try(provider.use_server_vrf, local.defaults.ndo.tenant_templates.tenant_policies.dhcp_relay_policies.providers.use_server_vrf)
          epg_path       = provider.type == "epg" ? "${provider.schema}/${provider.template}/${try(provider.application_profile, "")}/${try(provider.endpoint_group, "")}" : null
          ext_epg_path   = provider.type == "external_epg" ? "${provider.schema}/${provider.template}/${try(provider.external_endpoint_group, "")}" : null
        }]
      }
    ]
  ])
}

resource "mso_tenant_policies_dhcp_relay_policy" "tenant_policies_dhcp_relay_policy" {
  for_each    = { for policy in local.dhcp_relay_policies : policy.name => policy }
  name        = each.value.name
  template_id = mso_template.tenant_template[each.value.template_name].id
  description = each.value.description
  dynamic "dhcp_relay_providers" {
    for_each = { for provider in try(each.value.providers, []) : provider.name => provider if provider.type == "epg" }
    content {
      dhcp_server_address        = dhcp_relay_providers.value.ip
      application_epg_uuid       = !var.manage_schemas || (var.manage_schemas && !contains(local.managed_schemas, dhcp_relay_providers.value.schema)) ? data.mso_schema_template_anp_epg.schema_template_anp_epg[dhcp_relay_providers.value.epg_path].uuid : mso_schema_template_anp_epg.schema_template_anp_epg[dhcp_relay_providers.value.epg_path].uuid
      dhcp_server_vrf_preference = dhcp_relay_providers.value.use_server_vrf
    }
  }
  dynamic "dhcp_relay_providers" {
    for_each = { for provider in try(each.value.providers, []) : provider.name => provider if provider.type == "external_epg" }
    content {
      dhcp_server_address        = dhcp_relay_providers.value.ip
      external_epg_uuid          = !var.manage_schemas || (var.manage_schemas && !contains(local.managed_schemas, dhcp_relay_providers.value.schema)) ? data.mso_schema_template_external_epg.schema_template_external_epg[dhcp_relay_providers.value.ext_epg_path].uuid : mso_schema_template_external_epg.schema_template_external_epg[dhcp_relay_providers.value.ext_epg_path].uuid
      dhcp_server_vrf_preference = dhcp_relay_providers.value.use_server_vrf
    }
  }
}

locals {
  ipsla_policies = flatten([
    for template in local.tenant_templates : [
      for policy in try(template.ip_sla_policies, []) : {
        name               = policy.name
        template_name      = template.name
        description        = try(policy.description, null)
        sla_type           = try(policy.sla_type, local.defaults.ndo.tenant_templates.tenant_policies.ip_sla_policies.sla_type)
        destination_port   = try(policy.sla_type, local.defaults.ndo.tenant_templates.tenant_policies.ip_sla_policies.sla_type) == "http" ? 80 : try(policy.sla_type, local.defaults.ndo.tenant_templates.tenant_policies.ip_sla_policies.sla_type) == "tcp" ? try(policy.port, local.defaults.ndo.tenant_templates.tenant_policies.ip_sla_policies.port) : null
        http_version       = try(policy.http_version, local.defaults.ndo.tenant_templates.tenant_policies.ip_sla_policies.http_version)
        http_uri           = try(policy.http_uri, local.defaults.ndo.tenant_templates.tenant_policies.ip_sla_policies.http_uri)
        sla_frequency      = try(policy.frequency, local.defaults.ndo.tenant_templates.tenant_policies.ip_sla_policies.frequency)
        detect_multiplier  = try(policy.multiplier, local.defaults.ndo.tenant_templates.tenant_policies.ip_sla_policies.multiplier)
        request_data_size  = try(policy.request_data_size, local.defaults.ndo.tenant_templates.tenant_policies.ip_sla_policies.request_data_size)
        type_of_service    = try(policy.type_of_service, local.defaults.ndo.tenant_templates.tenant_policies.ip_sla_policies.type_of_service)
        operation_timeout  = try(policy.timeout, local.defaults.ndo.tenant_templates.tenant_policies.ip_sla_policies.timeout)
        threshold          = try(policy.threshold, local.defaults.ndo.tenant_templates.tenant_policies.ip_sla_policies.threshold)
        ipv6_traffic_class = try(policy.ipv6_traffic_class, local.defaults.ndo.tenant_templates.tenant_policies.ip_sla_policies.ipv6_traffic_class)
      }
    ]
  ])
}

resource "mso_tenant_policies_ipsla_monitoring_policy" "tenant_policies_ipsla_monitoring_policy" {
  for_each           = { for policy in local.ipsla_policies : policy.name => policy }
  template_id        = mso_template.tenant_template[each.value.template_name].id
  name               = each.value.name
  description        = each.value.description
  sla_type           = each.value.sla_type
  destination_port   = each.value.destination_port
  http_version       = each.value.http_version
  http_uri           = each.value.http_uri
  sla_frequency      = each.value.sla_frequency
  detect_multiplier  = each.value.detect_multiplier
  request_data_size  = each.value.request_data_size
  type_of_service    = each.value.type_of_service
  operation_timeout  = each.value.operation_timeout
  threshold          = each.value.threshold
  ipv6_traffic_class = each.value.ipv6_traffic_class
}

locals {
  multicast_route_maps = flatten([
    for template in local.tenant_templates : [
      for policy in try(template.multicast_route_maps, []) : {
        name          = policy.name
        template_name = template.name
        description   = try(policy.description, null)
        entries = [for entry in try(policy.entries, []) : {
          order               = entry.order
          group_ip            = entry.group_ip
          source_ip           = entry.source_ip
          rendezvous_point_ip = try(entry.rp_ip, local.defaults.ndo.tenant_templates.tenant_policies.multicast_route_maps.entries.rp_ip)
          action              = try(entry.action, local.defaults.ndo.tenant_templates.tenant_policies.multicast_route_maps.entries.action)
        }]
      }
    ]
  ])
}

resource "mso_tenant_policies_route_map_policy_multicast" "tenant_policies_route_map_policy_multicast" {
  for_each    = { for policy in local.multicast_route_maps : policy.name => policy }
  template_id = mso_template.tenant_template[each.value.template_name].id
  name        = each.value.name
  description = each.value.description
  dynamic "route_map_multicast_entries" {
    for_each = { for entry in try(each.value.entries, []) : entry.order => entry }
    content {
      order               = route_map_multicast_entries.value.order
      group_ip            = route_map_multicast_entries.value.group_ip
      source_ip           = route_map_multicast_entries.value.source_ip
      rendezvous_point_ip = route_map_multicast_entries.value.rendezvous_point_ip
      action              = route_map_multicast_entries.value.action
    }
  }
}