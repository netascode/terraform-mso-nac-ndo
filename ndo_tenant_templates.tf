locals {
  tenant_templates_tenants = [
    for template in local.tenant_templates : template.tenant
  ]
  template_ids = { for template in try(jsondecode(data.mso_rest.templates.content), []) : template.templateName => { "id" : template.templateId } if template.templateType == "tenantPolicy" }
}

data "mso_rest" "templates" {
  path = "api/v1/templates/summaries"
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
  for_each = toset(distinct([for site in local.tenant_templates_sites : site.site_name if(!var.manage_sites || local.ndo_platform_version == "4.1" || local.ndo_platform_version == "4.2") && var.manage_tenant_templates]))
  name     = each.value
}

locals {
  tenant_policies = flatten([
    for template in local.tenant_templates : [{
      name   = template.name
      tenant = contains(local.managed_tenants, template.tenant) ? mso_tenant.tenant[template.tenant].id : data.mso_tenant.tenant_templates_tenant[template.tenant].id
    sites = [for site in try(template.sites, []) : var.manage_sites && local.ndo_platform_version != "4.1" && local.ndo_platform_version != "4.2" ? mso_site.site[site].id : data.mso_site.tenant_templates_site[site].id] }]
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
          application_profile = try("${provider.application_profile}${local.defaults.ndo.schemas.templates.application_profiles.name_suffix}", null)
          endpoint_group      = try("${provider.endpoint_group}${local.defaults.ndo.schemas.templates.endpoint_groups.name_suffix}", null)
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
          external_endpoint_group = try("${provider.external_endpoint_group}${local.defaults.ndo.schemas.templates.external_endpoint_groups.name_suffix}", null)
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
          schema         = provider.schema
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
  name        = "${each.value.name}${local.defaults.ndo.tenant_templates.tenant_policies.dhcp_relay_policies.name_suffix}"
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

  depends_on = [
    mso_schema_template_anp_epg.schema_template_anp_epg,
    mso_schema_template_external_epg.schema_template_external_epg
  ]
}

locals {
  ipsla_policies = flatten([
    for template in local.tenant_templates : [
      for policy in try(template.ip_sla_policies, []) : {
        name               = "${policy.name}${local.defaults.ndo.tenant_templates.tenant_policies.ip_sla_policies.name_suffix}"
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
  ipsla_track_lists = flatten([
    for template in local.tenant_templates : [
      for policy in try(template.ip_sla_track_lists, []) : {
        name            = "${policy.name}${local.defaults.ndo.tenant_templates.tenant_policies.ip_sla_track_lists.name_suffix}"
        template_name   = template.name
        description     = try(policy.description, null)
        type            = try(policy.type, local.defaults.ndo.tenant_templates.tenant_policies.ip_sla_track_lists.type)
        percentage_up   = try(policy.percentage_up, local.defaults.ndo.tenant_templates.tenant_policies.ip_sla_track_lists.percentage_up)
        percentage_down = try(policy.percentage_down, local.defaults.ndo.tenant_templates.tenant_policies.ip_sla_track_lists.percentage_down)
        weight_up       = try(policy.weight_up, local.defaults.ndo.tenant_templates.tenant_policies.ip_sla_track_lists.weight_up)
        weight_down     = try(policy.weight_down, local.defaults.ndo.tenant_templates.tenant_policies.ip_sla_track_lists.weight_down)
        members = [for member in try(policy.members, []) : {
          destination_ip               = member.destination_ip
          ipsla_monitoring_policy_name = "${member.ip_sla_policy}${local.defaults.ndo.tenant_templates.tenant_policies.ip_sla_policies.name_suffix}"
          scope_type                   = member.scope_type
          scope_key                    = member.scope_type == "bd" ? "${member.schema}/${member.template}/${member.bridge_domain}" : "${member.schema}/${member.template}/${member.l3out}"
        }]
      }
    ]
  ])
}

resource "mso_tenant_policies_ipsla_track_list" "tenant_policies_ipsla_track_list" {
  for_each       = { for policy in local.ipsla_track_lists : policy.name => policy }
  template_id    = mso_template.tenant_template[each.value.template_name].id
  name           = each.value.name
  description    = each.value.description
  type           = each.value.type
  threshold_up   = each.value.type == "percentage" ? each.value.percentage_up : each.value.weight_up
  threshold_down = each.value.type == "percentage" ? each.value.percentage_down : each.value.weight_down

  dynamic "members" {
    for_each = each.value.members
    content {
      destination_ip               = members.value.destination_ip
      ipsla_monitoring_policy_uuid = mso_tenant_policies_ipsla_monitoring_policy.tenant_policies_ipsla_monitoring_policy[members.value.ipsla_monitoring_policy_name].uuid
      scope_type                   = members.value.scope_type
      scope_uuid                   = members.value.scope_type == "bd" ? mso_schema_template_bd.schema_template_bd[members.value.scope_key].uuid : mso_schema_template_l3out.schema_template_l3out[members.value.scope_key].uuid
    }
  }

  depends_on = [mso_tenant_policies_ipsla_monitoring_policy.tenant_policies_ipsla_monitoring_policy]
}

locals {
  multicast_route_maps = flatten([
    for template in local.tenant_templates : [
      for policy in try(template.multicast_route_maps, []) : {
        name          = "${policy.name}${local.defaults.ndo.tenant_templates.tenant_policies.multicast_route_maps.name_suffix}"
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

locals {
  bgp_peer_prefix_policies = flatten([
    for template in local.tenant_templates : [
      for policy in try(template.bgp_peer_prefix_policies, []) : {
        name          = "${policy.name}${local.defaults.ndo.tenant_templates.tenant_policies.bgp_peer_prefix_policies.name_suffix}"
        template_name = template.name
        description   = try(policy.description, null)
        action        = try(policy.action, local.defaults.ndo.tenant_templates.tenant_policies.bgp_peer_prefix_policies.action)
        max_prefixes  = try(policy.max_prefixes, local.defaults.ndo.tenant_templates.tenant_policies.bgp_peer_prefix_policies.max_prefixes)
        threshold     = try(policy.threshold, local.defaults.ndo.tenant_templates.tenant_policies.bgp_peer_prefix_policies.threshold)
        restart_time  = try(policy.restart_time, local.defaults.ndo.tenant_templates.tenant_policies.bgp_peer_prefix_policies.restart_time)
      }
    ]
  ])
}

resource "mso_tenant_policies_bgp_peer_prefix_policy" "tenant_policies_bgp_peer_prefix_policy" {
  for_each               = { for policy in local.bgp_peer_prefix_policies : policy.name => policy }
  template_id            = mso_template.tenant_template[each.value.template_name].id
  name                   = each.value.name
  description            = each.value.description
  action                 = each.value.action
  max_number_of_prefixes = each.value.max_prefixes
  threshold_percentage   = each.value.threshold
  restart_time           = each.value.restart_time
}

locals {
  dhcp_option_policies = flatten([
    for template in local.tenant_templates : [
      for policy in try(template.dhcp_option_policies, []) : {
        name          = "${policy.name}${local.defaults.ndo.tenant_templates.tenant_policies.dhcp_option_policies.name_suffix}"
        template_name = template.name
        description   = try(policy.description, null)
        options = [for option in try(policy.options, []) : {
          name = option.name
          id   = try(option.id, null)
          data = try(option.data, null)
        }]
      }
    ]
  ])
}

resource "mso_tenant_policies_dhcp_option_policy" "tenant_policies_dhcp_option_policy" {
  for_each    = { for policy in local.dhcp_option_policies : policy.name => policy }
  template_id = mso_template.tenant_template[each.value.template_name].id
  name        = each.value.name
  description = each.value.description

  dynamic "options" {
    for_each = each.value.options
    content {
      name = options.value.name
      id   = options.value.id
      data = options.value.data
    }
  }
}

locals {
  cos_int_to_name = {
    "0" = "background"
    "1" = "best_effort"
    "2" = "excellent_effort"
    "3" = "critical_applications"
    "4" = "video"
    "5" = "voice"
    "6" = "internetwork_control"
    "7" = "network_control"
  }
  custom_qos_policies = flatten([
    for template in local.tenant_templates : [
      for policy in try(template.custom_qos_policies, []) : {
        name          = "${policy.name}${local.defaults.ndo.tenant_templates.tenant_policies.custom_qos_policies.name_suffix}"
        template_name = template.name
        description   = try(policy.description, null)
        dscp_mappings = [for mapping in try(policy.dscp_mappings, []) : {
          dscp_from   = try(mapping.dscp_from, local.defaults.ndo.tenant_templates.tenant_policies.custom_qos_policies.dscp_mappings.dscp_from)
          dscp_to     = try(mapping.dscp_to, local.defaults.ndo.tenant_templates.tenant_policies.custom_qos_policies.dscp_mappings.dscp_to)
          dscp_target = try(mapping.dscp_target, local.defaults.ndo.tenant_templates.tenant_policies.custom_qos_policies.dscp_mappings.dscp_target)
          cos_target  = try(local.cos_int_to_name[tostring(try(mapping.cos_target, local.defaults.ndo.tenant_templates.tenant_policies.custom_qos_policies.dscp_mappings.cos_target))], try(mapping.cos_target, local.defaults.ndo.tenant_templates.tenant_policies.custom_qos_policies.dscp_mappings.cos_target))
          priority    = try(mapping.priority, local.defaults.ndo.tenant_templates.tenant_policies.custom_qos_policies.dscp_mappings.priority)
        }]
        cos_mappings = [for mapping in try(policy.cos_mappings, []) : {
          dot1p_from  = try(local.cos_int_to_name[tostring(try(mapping.dot1p_from, local.defaults.ndo.tenant_templates.tenant_policies.custom_qos_policies.cos_mappings.dot1p_from))], try(mapping.dot1p_from, local.defaults.ndo.tenant_templates.tenant_policies.custom_qos_policies.cos_mappings.dot1p_from))
          dot1p_to    = try(local.cos_int_to_name[tostring(try(mapping.dot1p_to, local.defaults.ndo.tenant_templates.tenant_policies.custom_qos_policies.cos_mappings.dot1p_to))], try(mapping.dot1p_to, local.defaults.ndo.tenant_templates.tenant_policies.custom_qos_policies.cos_mappings.dot1p_to))
          dscp_target = try(mapping.dscp_target, local.defaults.ndo.tenant_templates.tenant_policies.custom_qos_policies.cos_mappings.dscp_target)
          cos_target  = try(local.cos_int_to_name[tostring(try(mapping.cos_target, local.defaults.ndo.tenant_templates.tenant_policies.custom_qos_policies.cos_mappings.cos_target))], try(mapping.cos_target, local.defaults.ndo.tenant_templates.tenant_policies.custom_qos_policies.cos_mappings.cos_target))
          priority    = try(mapping.priority, local.defaults.ndo.tenant_templates.tenant_policies.custom_qos_policies.cos_mappings.priority)
        }]
      }
    ]
  ])
}

resource "mso_tenant_policies_custom_qos_policy" "tenant_policies_custom_qos_policy" {
  for_each    = { for policy in local.custom_qos_policies : policy.name => policy }
  template_id = mso_template.tenant_template[each.value.template_name].id
  name        = each.value.name
  description = each.value.description

  dynamic "dscp_mappings" {
    for_each = each.value.dscp_mappings
    content {
      dscp_from    = dscp_mappings.value.dscp_from
      dscp_to      = dscp_mappings.value.dscp_to
      dscp_target  = dscp_mappings.value.dscp_target
      target_cos   = dscp_mappings.value.cos_target
      qos_priority = dscp_mappings.value.priority
    }
  }

  dynamic "cos_mappings" {
    for_each = each.value.cos_mappings
    content {
      dot1p_from   = cos_mappings.value.dot1p_from
      dot1p_to     = cos_mappings.value.dot1p_to
      dscp_target  = cos_mappings.value.dscp_target
      target_cos   = cos_mappings.value.cos_target
      qos_priority = cos_mappings.value.priority
    }
  }
}

locals {
  l3out_interface_routing_policies = flatten([
    for template in local.tenant_templates : [
      for policy in try(template.l3out_interface_routing_policies, []) : {
        name          = "${policy.name}${local.defaults.ndo.tenant_templates.tenant_policies.l3out_interface_routing_policies.name_suffix}"
        template_name = template.name
        description   = try(policy.description, null)
        bfd_multi_hop_settings = try(policy.bfd_multi_hop_settings, null) != null ? {
          admin_state           = try(policy.bfd_multi_hop_settings.admin_state, local.defaults.ndo.tenant_templates.tenant_policies.l3out_interface_routing_policies.bfd_multi_hop_settings.admin_state) != null ? (policy.bfd_multi_hop_settings.admin_state ? "enabled" : "disabled") : null
          detection_multiplier  = try(policy.bfd_multi_hop_settings.detection_multiplier, local.defaults.ndo.tenant_templates.tenant_policies.l3out_interface_routing_policies.bfd_multi_hop_settings.detection_multiplier)
          min_receive_interval  = try(policy.bfd_multi_hop_settings.min_rx_interval, local.defaults.ndo.tenant_templates.tenant_policies.l3out_interface_routing_policies.bfd_multi_hop_settings.min_rx_interval)
          min_transmit_interval = try(policy.bfd_multi_hop_settings.min_tx_interval, local.defaults.ndo.tenant_templates.tenant_policies.l3out_interface_routing_policies.bfd_multi_hop_settings.min_tx_interval)
        } : null
        bfd_settings = try(policy.bfd_settings, null) != null ? {
          admin_state           = try(policy.bfd_settings.admin_state, local.defaults.ndo.tenant_templates.tenant_policies.l3out_interface_routing_policies.bfd_settings.admin_state) ? "enabled" : "disabled"
          detection_multiplier  = try(policy.bfd_settings.detection_multiplier, local.defaults.ndo.tenant_templates.tenant_policies.l3out_interface_routing_policies.bfd_settings.detection_multiplier)
          min_receive_interval  = try(policy.bfd_settings.min_rx_interval, local.defaults.ndo.tenant_templates.tenant_policies.l3out_interface_routing_policies.bfd_settings.min_rx_interval)
          min_transmit_interval = try(policy.bfd_settings.min_tx_interval, local.defaults.ndo.tenant_templates.tenant_policies.l3out_interface_routing_policies.bfd_settings.min_tx_interval)
          echo_receive_interval = try(policy.bfd_settings.echo_rx_interval, local.defaults.ndo.tenant_templates.tenant_policies.l3out_interface_routing_policies.bfd_settings.echo_rx_interval)
          echo_admin_state      = try(policy.bfd_settings.echo_admin_state, local.defaults.ndo.tenant_templates.tenant_policies.l3out_interface_routing_policies.bfd_settings.echo_admin_state) ? "enabled" : "disabled"
          interface_control     = try(policy.bfd_settings.interface_control, local.defaults.ndo.tenant_templates.tenant_policies.l3out_interface_routing_policies.bfd_settings.interface_control)
        } : null
        ospf_interface_settings = try(policy.ospf_interface_settings, null) != null ? {
          network_type          = try(policy.ospf_interface_settings.network_type, local.defaults.ndo.tenant_templates.tenant_policies.l3out_interface_routing_policies.ospf_interface_settings.network_type) == "point-to-point" ? "point_to_point" : try(policy.ospf_interface_settings.network_type, local.defaults.ndo.tenant_templates.tenant_policies.l3out_interface_routing_policies.ospf_interface_settings.network_type) == "broadcast" ? "broadcast" : null
          priority              = try(policy.ospf_interface_settings.priority, local.defaults.ndo.tenant_templates.tenant_policies.l3out_interface_routing_policies.ospf_interface_settings.priority)
          interface_cost        = try(policy.ospf_interface_settings.interface_cost, local.defaults.ndo.tenant_templates.tenant_policies.l3out_interface_routing_policies.ospf_interface_settings.interface_cost)
          hello_interval        = try(policy.ospf_interface_settings.hello_interval, local.defaults.ndo.tenant_templates.tenant_policies.l3out_interface_routing_policies.ospf_interface_settings.hello_interval)
          dead_interval         = try(policy.ospf_interface_settings.dead_interval, local.defaults.ndo.tenant_templates.tenant_policies.l3out_interface_routing_policies.ospf_interface_settings.dead_interval)
          retransmit_interval   = try(policy.ospf_interface_settings.retransmit_interval, local.defaults.ndo.tenant_templates.tenant_policies.l3out_interface_routing_policies.ospf_interface_settings.retransmit_interval)
          transmit_delay        = try(policy.ospf_interface_settings.transmit_delay, local.defaults.ndo.tenant_templates.tenant_policies.l3out_interface_routing_policies.ospf_interface_settings.transmit_delay)
          advertise_subnet      = try(policy.ospf_interface_settings.advertise_subnet, local.defaults.ndo.tenant_templates.tenant_policies.l3out_interface_routing_policies.ospf_interface_settings.advertise_subnet)
          bfd                   = try(policy.ospf_interface_settings.bfd, local.defaults.ndo.tenant_templates.tenant_policies.l3out_interface_routing_policies.ospf_interface_settings.bfd)
          mtu_ignore            = try(policy.ospf_interface_settings.mtu_ignore, local.defaults.ndo.tenant_templates.tenant_policies.l3out_interface_routing_policies.ospf_interface_settings.mtu_ignore)
          passive_participation = try(policy.ospf_interface_settings.passive_participation, local.defaults.ndo.tenant_templates.tenant_policies.l3out_interface_routing_policies.ospf_interface_settings.passive_participation)
        } : null
      }
    ]
  ])
}

resource "mso_tenant_policies_l3out_interface_routing_policy" "tenant_policies_l3out_interface_routing_policy" {
  for_each    = { for policy in local.l3out_interface_routing_policies : policy.name => policy }
  template_id = mso_template.tenant_template[each.value.template_name].id
  name        = each.value.name
  description = each.value.description

  dynamic "bfd_multi_hop_settings" {
    for_each = each.value.bfd_multi_hop_settings != null ? [each.value.bfd_multi_hop_settings] : []
    content {
      admin_state           = bfd_multi_hop_settings.value.admin_state
      detection_multiplier  = bfd_multi_hop_settings.value.detection_multiplier
      min_receive_interval  = bfd_multi_hop_settings.value.min_receive_interval
      min_transmit_interval = bfd_multi_hop_settings.value.min_transmit_interval
    }
  }

  dynamic "bfd_settings" {
    for_each = each.value.bfd_settings != null ? [each.value.bfd_settings] : []
    content {
      admin_state           = bfd_settings.value.admin_state
      detection_multiplier  = bfd_settings.value.detection_multiplier
      min_receive_interval  = bfd_settings.value.min_receive_interval
      min_transmit_interval = bfd_settings.value.min_transmit_interval
      echo_receive_interval = bfd_settings.value.echo_receive_interval
      echo_admin_state      = bfd_settings.value.echo_admin_state
      interface_control     = bfd_settings.value.interface_control
    }
  }

  dynamic "ospf_interface_settings" {
    for_each = each.value.ospf_interface_settings != null ? [each.value.ospf_interface_settings] : []
    content {
      network_type          = ospf_interface_settings.value.network_type
      priority              = ospf_interface_settings.value.priority
      cost_of_interface     = ospf_interface_settings.value.interface_cost
      hello_interval        = ospf_interface_settings.value.hello_interval
      dead_interval         = ospf_interface_settings.value.dead_interval
      retransmit_interval   = ospf_interface_settings.value.retransmit_interval
      transmit_delay        = ospf_interface_settings.value.transmit_delay
      advertise_subnet      = ospf_interface_settings.value.advertise_subnet
      bfd                   = ospf_interface_settings.value.bfd
      mtu_ignore            = ospf_interface_settings.value.mtu_ignore
      passive_participation = ospf_interface_settings.value.passive_participation
    }
  }
}

locals {
  mld_snooping_policies = flatten([
    for template in local.tenant_templates : [
      for policy in try(template.mld_snooping_policies, []) : {
        name                       = "${policy.name}${local.defaults.ndo.tenant_templates.tenant_policies.mld_snooping_policies.name_suffix}"
        template_name              = template.name
        description                = try(policy.description, null)
        admin_state                = try(policy.admin_state, local.defaults.ndo.tenant_templates.tenant_policies.mld_snooping_policies.admin_state) ? "enabled" : "disabled"
        fast_leave_control         = try(policy.fast_leave_control, local.defaults.ndo.tenant_templates.tenant_policies.mld_snooping_policies.fast_leave_control)
        querier_control            = try(policy.querier_control, local.defaults.ndo.tenant_templates.tenant_policies.mld_snooping_policies.querier_control)
        querier_version            = try(policy.querier_version, local.defaults.ndo.tenant_templates.tenant_policies.mld_snooping_policies.querier_version)
        query_interval             = try(policy.query_interval, local.defaults.ndo.tenant_templates.tenant_policies.mld_snooping_policies.query_interval)
        query_response_interval    = try(policy.query_response_interval, local.defaults.ndo.tenant_templates.tenant_policies.mld_snooping_policies.query_response_interval)
        last_member_query_interval = try(policy.last_member_query_interval, local.defaults.ndo.tenant_templates.tenant_policies.mld_snooping_policies.last_member_query_interval)
        start_query_interval       = try(policy.start_query_interval, local.defaults.ndo.tenant_templates.tenant_policies.mld_snooping_policies.start_query_interval)
        start_query_count          = try(policy.start_query_count, local.defaults.ndo.tenant_templates.tenant_policies.mld_snooping_policies.start_query_count)
      }
    ]
  ])
}

resource "mso_tenant_policies_mld_snooping_policy" "tenant_policies_mld_snooping_policy" {
  for_each                   = { for policy in local.mld_snooping_policies : policy.name => policy }
  template_id                = mso_template.tenant_template[each.value.template_name].id
  name                       = each.value.name
  description                = each.value.description
  admin_state                = each.value.admin_state
  fast_leave_control         = each.value.fast_leave_control
  querier_control            = each.value.querier_control
  querier_version            = each.value.querier_version
  query_interval             = each.value.query_interval
  query_response_interval    = each.value.query_response_interval
  last_member_query_interval = each.value.last_member_query_interval
  start_query_interval       = each.value.start_query_interval
  start_query_count          = each.value.start_query_count
}

locals {
  netflow_record_match_map = {
    "dst-ip"    = "destination_ip"
    "dst-ipv4"  = "destination_ipv4"
    "dst-ipv6"  = "destination_ipv6"
    "dst-mac"   = "destination_mac"
    "dst-port"  = "destination_port"
    "ethertype" = "ethertype"
    "proto"     = "ip_protocol"
    "src-ip"    = "source_ip"
    "src-ipv4"  = "source_ipv4"
    "src-ipv6"  = "source_ipv6"
    "src-mac"   = "source_mac"
    "src-port"  = "source_port"
  }
  netflow_records = flatten([
    for template in local.tenant_templates : [
      for policy in try(template.netflow_records, []) : {
        name             = "${policy.name}${local.defaults.ndo.tenant_templates.tenant_policies.netflow_records.name_suffix}"
        template_name    = template.name
        description      = try(policy.description, null)
        match_parameters = try([for param in policy.match_parameters : local.netflow_record_match_map[param]], null)
      }
    ]
  ])
}

resource "mso_tenant_policies_netflow_record" "tenant_policies_netflow_record" {
  for_each         = { for policy in local.netflow_records : policy.name => policy }
  template_id      = mso_template.tenant_template[each.value.template_name].id
  name             = each.value.name
  description      = each.value.description
  match_parameters = each.value.match_parameters
}

locals {
  netflow_exporters = flatten([
    for template in local.tenant_templates : [
      for policy in try(template.netflow_exporters, []) : {
        name          = "${policy.name}${local.defaults.ndo.tenant_templates.tenant_policies.netflow_exporters.name_suffix}"
        template_name = template.name
      }
    ]
  ])
}

resource "mso_tenant_policies_netflow_exporter" "tenant_policies_netflow_exporter" {
  for_each    = { for policy in local.netflow_exporters : policy.name => policy }
  template_id = mso_template.tenant_template[each.value.template_name].id
  name        = each.value.name
}

locals {
  netflow_monitors = flatten([
    for template in local.tenant_templates : [
      for policy in try(template.netflow_monitors, []) : {
        name                  = "${policy.name}${local.defaults.ndo.tenant_templates.tenant_policies.netflow_monitors.name_suffix}"
        template_name         = template.name
        description           = try(policy.description, null)
        netflow_record_name   = try("${policy.netflow_record}${local.defaults.ndo.tenant_templates.tenant_policies.netflow_records.name_suffix}", null)
        netflow_exporter_keys = [for exporter in try(policy.netflow_exporters, []) : "${exporter}${local.defaults.ndo.tenant_templates.tenant_policies.netflow_exporters.name_suffix}"]
      }
    ]
  ])
}

resource "mso_tenant_policies_netflow_monitor" "tenant_policies_netflow_monitor" {
  for_each               = { for policy in local.netflow_monitors : policy.name => policy }
  template_id            = mso_template.tenant_template[each.value.template_name].id
  name                   = each.value.name
  description            = each.value.description
  netflow_record_uuid    = each.value.netflow_record_name != null ? mso_tenant_policies_netflow_record.tenant_policies_netflow_record[each.value.netflow_record_name].uuid : null
  netflow_exporter_uuids = [for exporter_name in each.value.netflow_exporter_keys : mso_tenant_policies_netflow_exporter.tenant_policies_netflow_exporter[exporter_name].uuid]

  depends_on = [
    mso_tenant_policies_netflow_record.tenant_policies_netflow_record,
    mso_tenant_policies_netflow_exporter.tenant_policies_netflow_exporter,
  ]
}

locals {
  igmp_interface_policies = flatten([
    for template in local.tenant_templates : [
      for policy in try(template.igmp_interface_policies, []) : {
        name                         = "${policy.name}${local.defaults.ndo.tenant_templates.tenant_policies.igmp_interface_policies.name_suffix}"
        template_name                = template.name
        description                  = try(policy.description, null)
        version3_asm                 = try(policy.version3_asm, local.defaults.ndo.tenant_templates.tenant_policies.igmp_interface_policies.version3_asm)
        fast_leave                   = try(policy.fast_leave, local.defaults.ndo.tenant_templates.tenant_policies.igmp_interface_policies.fast_leave)
        report_link_local_groups     = try(policy.report_link_local_groups, local.defaults.ndo.tenant_templates.tenant_policies.igmp_interface_policies.report_link_local_groups)
        igmp_version                 = try(policy.igmp_version, local.defaults.ndo.tenant_templates.tenant_policies.igmp_interface_policies.igmp_version)
        group_timeout                = try(policy.group_timeout, local.defaults.ndo.tenant_templates.tenant_policies.igmp_interface_policies.group_timeout)
        query_interval               = try(policy.query_interval, local.defaults.ndo.tenant_templates.tenant_policies.igmp_interface_policies.query_interval)
        query_response_interval      = try(policy.query_response_interval, local.defaults.ndo.tenant_templates.tenant_policies.igmp_interface_policies.query_response_interval)
        last_member_count            = try(policy.last_member_count, local.defaults.ndo.tenant_templates.tenant_policies.igmp_interface_policies.last_member_count)
        last_member_response_time    = try(policy.last_member_response_time, local.defaults.ndo.tenant_templates.tenant_policies.igmp_interface_policies.last_member_response_time)
        startup_query_count          = try(policy.startup_query_count, local.defaults.ndo.tenant_templates.tenant_policies.igmp_interface_policies.startup_query_count)
        startup_query_interval       = try(policy.startup_query_interval, local.defaults.ndo.tenant_templates.tenant_policies.igmp_interface_policies.startup_query_interval)
        querier_timeout              = try(policy.querier_timeout, local.defaults.ndo.tenant_templates.tenant_policies.igmp_interface_policies.querier_timeout)
        robustness_variable          = try(policy.robustness_variable, local.defaults.ndo.tenant_templates.tenant_policies.igmp_interface_policies.robustness_variable)
        maximum_multicast_entries    = try(policy.maximum_multicast_entries, null)
        reserved_multicast_entries   = try(policy.reserved_multicast_entries, local.defaults.ndo.tenant_templates.tenant_policies.igmp_interface_policies.reserved_multicast_entries)
        state_limit_route_map_name   = try("${policy.state_limit_route_map}${local.defaults.ndo.tenant_templates.tenant_policies.multicast_route_maps.name_suffix}", null)
        report_policy_route_map_name = try("${policy.report_policy_route_map}${local.defaults.ndo.tenant_templates.tenant_policies.multicast_route_maps.name_suffix}", null)
        static_report_route_map_name = try("${policy.static_report_route_map}${local.defaults.ndo.tenant_templates.tenant_policies.multicast_route_maps.name_suffix}", null)
      }
    ]
  ])
}

resource "mso_tenant_policies_igmp_interface_policy" "tenant_policies_igmp_interface_policy" {
  for_each                     = { for policy in local.igmp_interface_policies : policy.name => policy }
  template_id                  = mso_template.tenant_template[each.value.template_name].id
  name                         = each.value.name
  description                  = each.value.description
  version3_asm                 = each.value.version3_asm
  fast_leave                   = each.value.fast_leave
  report_link_local_groups     = each.value.report_link_local_groups
  igmp_version                 = each.value.igmp_version
  group_timeout                = each.value.group_timeout
  query_interval               = each.value.query_interval
  query_response_interval      = each.value.query_response_interval
  last_member_count            = each.value.last_member_count
  last_member_response_time    = each.value.last_member_response_time
  startup_query_count          = each.value.startup_query_count
  startup_query_interval       = each.value.startup_query_interval
  querier_timeout              = each.value.querier_timeout
  robustness_variable          = each.value.robustness_variable
  maximum_multicast_entries    = each.value.maximum_multicast_entries
  reserved_multicast_entries   = each.value.reserved_multicast_entries
  state_limit_route_map_uuid   = each.value.state_limit_route_map_name != null ? mso_tenant_policies_route_map_policy_multicast.tenant_policies_route_map_policy_multicast[each.value.state_limit_route_map_name].uuid : null
  report_policy_route_map_uuid = each.value.report_policy_route_map_name != null ? mso_tenant_policies_route_map_policy_multicast.tenant_policies_route_map_policy_multicast[each.value.report_policy_route_map_name].uuid : null
  static_report_route_map_uuid = each.value.static_report_route_map_name != null ? mso_tenant_policies_route_map_policy_multicast.tenant_policies_route_map_policy_multicast[each.value.static_report_route_map_name].uuid : null

  depends_on = [mso_tenant_policies_route_map_policy_multicast.tenant_policies_route_map_policy_multicast]
}

locals {
  endpoint_mac_tag_policies = flatten([
    for template in local.tenant_templates : [
      for policy in try(template.endpoint_mac_tag_policies, []) : {
        key             = "${template.name}/${policy.mac}"
        template_name   = template.name
        mac             = policy.mac
        scope_type      = policy.scope_type
        scope_key       = policy.scope_type == "bd" ? "${policy.schema}/${policy.template}/${policy.bridge_domain}" : "${policy.schema}/${policy.template}/${policy.vrf}"
        tag_annotations = try(policy.tag_annotations, [])
        policy_tags     = try(policy.policy_tags, [])
      }
    ]
  ])
}

resource "mso_tenant_policies_endpoint_mac_tag_policy" "tenant_policies_endpoint_mac_tag_policy" {
  for_each    = { for policy in local.endpoint_mac_tag_policies : policy.key => policy }
  template_id = mso_template.tenant_template[each.value.template_name].id
  mac         = each.value.mac
  bd_uuid     = each.value.scope_type == "bd" ? mso_schema_template_bd.schema_template_bd[each.value.scope_key].uuid : null
  vrf_uuid    = each.value.scope_type == "vrf" ? mso_schema_template_vrf.schema_template_vrf[each.value.scope_key].uuid : null

  dynamic "tag_annotations" {
    for_each = each.value.tag_annotations
    content {
      key   = tag_annotations.value.key
      value = tag_annotations.value.value
    }
  }

  dynamic "policy_tags" {
    for_each = each.value.policy_tags
    content {
      key   = policy_tags.value.key
      value = policy_tags.value.value
    }
  }
}