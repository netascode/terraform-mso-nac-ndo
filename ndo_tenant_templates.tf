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
  for_each = toset(distinct([for site in local.tenant_templates_sites : site.site_name if(!var.manage_sites || local.ndo_platform_version == "4.1") && var.manage_tenant_templates]))
  name     = each.value
}

locals {
  tenant_policies = flatten([
    for template in local.tenant_templates : [{
      name   = template.name
      tenant = contains(local.managed_tenants, template.tenant) ? mso_tenant.tenant[template.tenant].id : data.mso_tenant.tenant_templates_tenant[template.tenant].id
    sites = [for site in try(template.sites, []) : var.manage_sites && local.ndo_platform_version != "4.1" ? mso_site.site[site].id : data.mso_site.tenant_templates_site[site].id] }]
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
  service_device_policies = flatten([
    for template in local.service_device_templates : [{
      name   = template.name
      tenant = contains(local.managed_tenants, template.tenant) ? mso_tenant.tenant[template.tenant].id : data.mso_tenant.tenant_templates_tenant[template.tenant].id
      sites  = [for site in try(template.sites, []) : var.manage_sites && local.ndo_platform_version != "4.1" ? mso_site.site[site].id : data.mso_site.tenant_templates_site[site].id]
    }]
  ])
}



resource "mso_template" "service_device_template" {
  for_each      = { for template in local.service_device_policies : template.name => template }
  template_name = each.value.name
  template_type = "service_device"
  tenant_id     = each.value.tenant
  sites         = each.value.sites
}

locals {
  service_device_clusters = flatten([
    for template in local.service_device_templates : [
      for cluster in try(template.cluster, []) : {
        key           = "service_device/${template.name}/${cluster.name}"
        template_name = template.name
        name          = cluster.name
        device_type   = try(cluster.device_type, "firewall")
        device_mode   = try(cluster.device_mode, local.defaults.ndo.tenant_templates.service_device.cluster.device_mode)
        interfaces = [for iface in try(cluster.interfaces, []) : {
          name                      = iface.name
          interface_type            = try(iface.interface_type, local.defaults.ndo.tenant_templates.service_device.cluster.interfaces.interface_type)
          bd_uuid_key               = try(iface.interface_type, local.defaults.ndo.tenant_templates.service_device.cluster.interfaces.interface_type) == "bd" ? "${try(iface.schema, "")}/${try(iface.template, "")}/${try(iface.bridge_domain, "")}" : null
          external_epg_uuid_key     = try(iface.interface_type, local.defaults.ndo.tenant_templates.service_device.cluster.interfaces.interface_type) == "l3out" ? "${try(iface.schema, "")}/${try(iface.template, "")}/${try(iface.external_endpoint_group, "")}" : null
          redirect                  = try(iface.redirect, local.defaults.ndo.tenant_templates.service_device.cluster.interfaces.redirect)
          ipsla_key                 = try(iface.ip_sla, null) != null ? "${try(iface.ip_sla.template, template.name)}/${try(iface.ip_sla.name, "")}" : null
          advanced_tracking_options = try(iface.ip_sla, null) != null || try(iface.advanced_tracking_options, local.defaults.ndo.tenant_templates.service_device.cluster.interfaces.advanced_tracking_options)
          preferred_group           = try(iface.preferred_group, local.defaults.ndo.tenant_templates.service_device.cluster.interfaces.preferred_group)
          rewrite_source_mac        = try(iface.rewrite_source_mac, null)
          anycast                   = try(iface.anycast, null)
          config_static_mac         = (try(iface.ip_sla, null) != null || try(iface.advanced_tracking_options, local.defaults.ndo.tenant_templates.service_device.cluster.interfaces.advanced_tracking_options)) ? try(iface.static_mac, local.defaults.ndo.tenant_templates.service_device.cluster.interfaces.config_static_mac) : null
          is_backup_redirect_ip     = (try(iface.ip_sla, null) != null || try(iface.advanced_tracking_options, local.defaults.ndo.tenant_templates.service_device.cluster.interfaces.advanced_tracking_options)) ? try(iface.backup_redirect_ip, local.defaults.ndo.tenant_templates.service_device.cluster.interfaces.backup_redirect_ip) : null
          load_balance_hashing      = try(iface.load_balance_hashing, null)
          pod_aware_redirection     = try(iface.pod_aware_redirection, null)
          resilient_hashing         = (try(iface.ip_sla, null) != null || try(iface.advanced_tracking_options, local.defaults.ndo.tenant_templates.service_device.cluster.interfaces.advanced_tracking_options)) ? try(iface.resilient_hash, local.defaults.ndo.tenant_templates.service_device.cluster.interfaces.resilient_hash) : null
          tag_based_sorting         = (try(iface.ip_sla, null) != null || try(iface.advanced_tracking_options, local.defaults.ndo.tenant_templates.service_device.cluster.interfaces.advanced_tracking_options)) ? try(iface.tag_based_sorting, local.defaults.ndo.tenant_templates.service_device.cluster.interfaces.tag_based_sorting) : null
          min_threshold             = (try(iface.ip_sla, null) != null || try(iface.advanced_tracking_options, local.defaults.ndo.tenant_templates.service_device.cluster.interfaces.advanced_tracking_options)) && try(cluster.device_mode, local.defaults.ndo.tenant_templates.service_device.cluster.device_mode) == "layer3" ? try(iface.threshold.min_threshold, local.defaults.ndo.tenant_templates.service_device.cluster.interfaces.threshold.min_threshold) : null
          max_threshold             = (try(iface.ip_sla, null) != null || try(iface.advanced_tracking_options, local.defaults.ndo.tenant_templates.service_device.cluster.interfaces.advanced_tracking_options)) && try(cluster.device_mode, local.defaults.ndo.tenant_templates.service_device.cluster.device_mode) == "layer3" ? try(iface.threshold.max_threshold, local.defaults.ndo.tenant_templates.service_device.cluster.interfaces.threshold.max_threshold) : null
          threshold_down_action     = (try(iface.ip_sla, null) != null || try(iface.advanced_tracking_options, local.defaults.ndo.tenant_templates.service_device.cluster.interfaces.advanced_tracking_options)) && try(cluster.device_mode, local.defaults.ndo.tenant_templates.service_device.cluster.device_mode) == "layer3" ? try(iface.threshold.down_action, local.defaults.ndo.tenant_templates.service_device.cluster.interfaces.threshold.down_action) : null
        }]
      }
    ]
  ])

  service_device_bd_lookups = distinct(flatten([
    for cluster in local.service_device_clusters : [
      for iface in cluster.interfaces : {
        key      = iface.bd_uuid_key
        schema   = split("/", iface.bd_uuid_key)[0]
        template = split("/", iface.bd_uuid_key)[1]
        name     = split("/", iface.bd_uuid_key)[2]
      } if iface.bd_uuid_key != null
    ]
  ]))

  service_device_external_epg_lookups = distinct(flatten([
    for cluster in local.service_device_clusters : [
      for iface in cluster.interfaces : {
        key      = iface.external_epg_uuid_key
        schema   = split("/", iface.external_epg_uuid_key)[0]
        template = split("/", iface.external_epg_uuid_key)[1]
        name     = split("/", iface.external_epg_uuid_key)[2]
      } if iface.external_epg_uuid_key != null
    ]
  ]))


}

data "mso_schema_template_bd" "service_device_bd" {
  for_each      = { for bd in local.service_device_bd_lookups : bd.key => bd if(!var.manage_schemas || (var.manage_schemas && !contains(local.managed_schemas, bd.schema))) }
  schema_id     = local.schema_ids[each.value.schema].id
  template_name = each.value.template
  name          = each.value.name
}

data "mso_schema_template_external_epg" "service_device_external_epg" {
  for_each          = { for epg in local.service_device_external_epg_lookups : epg.key => epg if(!var.manage_schemas || (var.manage_schemas && !contains(local.managed_schemas, epg.schema))) }
  schema_id         = local.schema_ids[each.value.schema].id
  template_name     = each.value.template
  external_epg_name = each.value.name
}



resource "mso_service_device_cluster" "service_device_cluster" {
  for_each    = { for cluster in local.service_device_clusters : cluster.key => cluster }
  template_id = mso_template.service_device_template[each.value.template_name].id
  name        = each.value.name
  device_type = each.value.device_type
  device_mode = each.value.device_mode
  dynamic "interface_properties" {
    for_each = { for iface in each.value.interfaces : iface.name => iface }
    content {
      name                         = interface_properties.value.name
      redirect                     = interface_properties.value.redirect
      bd_uuid                      = interface_properties.value.bd_uuid_key != null ? (!var.manage_schemas || (var.manage_schemas && !contains(local.managed_schemas, split("/", interface_properties.value.bd_uuid_key)[0])) ? data.mso_schema_template_bd.service_device_bd[interface_properties.value.bd_uuid_key].uuid : mso_schema_template_bd.schema_template_bd["${split("/", interface_properties.value.bd_uuid_key)[0]}/${split("/", interface_properties.value.bd_uuid_key)[1]}/${split("/", interface_properties.value.bd_uuid_key)[2]}"].uuid) : null
      external_epg_uuid            = interface_properties.value.external_epg_uuid_key != null ? (!var.manage_schemas || (var.manage_schemas && !contains(local.managed_schemas, split("/", interface_properties.value.external_epg_uuid_key)[0])) ? data.mso_schema_template_external_epg.service_device_external_epg[interface_properties.value.external_epg_uuid_key].uuid : mso_schema_template_external_epg.schema_template_external_epg["${split("/", interface_properties.value.external_epg_uuid_key)[0]}/${split("/", interface_properties.value.external_epg_uuid_key)[1]}/${split("/", interface_properties.value.external_epg_uuid_key)[2]}"].uuid) : null
      ipsla_monitoring_policy_uuid = interface_properties.value.ipsla_key != null ? mso_tenant_policies_ipsla_monitoring_policy.tenant_policies_ipsla_monitoring_policy[split("/", interface_properties.value.ipsla_key)[1]].uuid : null
      preferred_group              = interface_properties.value.preferred_group
      rewrite_source_mac           = interface_properties.value.rewrite_source_mac
      anycast                      = interface_properties.value.anycast
      config_static_mac            = interface_properties.value.config_static_mac
      is_backup_redirect_ip        = interface_properties.value.is_backup_redirect_ip
      load_balance_hashing         = interface_properties.value.load_balance_hashing
      pod_aware_redirection        = interface_properties.value.pod_aware_redirection
      resilient_hashing            = interface_properties.value.resilient_hashing
      tag_based_sorting            = interface_properties.value.tag_based_sorting
      min_threshold                = interface_properties.value.min_threshold
      max_threshold                = interface_properties.value.max_threshold
      threshold_down_action        = interface_properties.value.threshold_down_action
    }
  }
  depends_on = [
    mso_schema_template_bd.schema_template_bd,
    mso_schema_template_external_epg.schema_template_external_epg,
    mso_tenant_policies_ipsla_monitoring_policy.tenant_policies_ipsla_monitoring_policy,
  ]
}

locals {
  service_device_cluster_sites = flatten([
    for template in local.service_device_templates : [
      for cluster in try(template.cluster, []) : [
        for site_name in try(template.sites, []) : [
          for site in [try([for s in try(cluster.sites, []) : s if s.name == site_name][0], {})] : {
            key                    = "service_device/${template.name}/${cluster.name}/${site_name}"
            template_name          = template.name
            cluster_name           = cluster.name
            site_name              = site_name
            site_id                = var.manage_sites && local.ndo_platform_version != "4.1" ? mso_site.site[site_name].id : data.mso_site.tenant_templates_site[site_name].id
            device_mode            = try(cluster.device_mode, local.defaults.ndo.tenant_templates.service_device.cluster.device_mode)
            domain_type            = try(site.domain_type, local.defaults.ndo.tenant_templates.service_device.cluster.sites.domain_type)
            domain_name            = try(site.domain_name, null)
            vmm_type               = try(site.vmm_type, local.defaults.ndo.tenant_templates.service_device.cluster.sites.vmm_type)
            trunking_port          = try(site.trunking_port, local.defaults.ndo.tenant_templates.service_device.cluster.sites.trunking_port)
            promiscuous_mode       = try(site.promiscuous_mode, local.defaults.ndo.tenant_templates.service_device.cluster.sites.promiscuous_mode)
            site_vlan              = try(site.site_vlan, null)
            high_availability_mode = contains(["layer2", "layer1"], try(cluster.device_mode, local.defaults.ndo.tenant_templates.service_device.cluster.device_mode)) ? try(site.high_availability_mode, local.defaults.ndo.tenant_templates.service_device.cluster.sites.high_availability_mode) : null

            interfaces = [for iface in try(cluster.interfaces, []) : [
              for iface_site in [try([for s in try(iface.sites, []) : s if s.name == site_name][0], {})] : {
                name        = iface.name
                vlan        = try(iface.vlan, null)
                elag        = try(site.domain_type, local.defaults.ndo.tenant_templates.service_device.cluster.sites.domain_type) == "vmm" ? try(iface_site.elag, null) : null
                domain_name = try(iface_site.domain_name, null)

                pbr_destinations = (try(iface.ip_sla, null) != null || try(iface.redirect, local.defaults.ndo.tenant_templates.service_device.cluster.interfaces.redirect)) ? [for pbr in try(iface_site.pbr_destinations, []) : {
                  ip                     = try(pbr.ip, null)
                  mac                    = try(pbr.mac, null)
                  tag                    = try(pbr.tag, null)
                  pod_id                 = try(iface.pod_aware_redirection, local.defaults.ndo.tenant_templates.service_device.cluster.interfaces.pod_aware_redirection) ? try(pbr.pod_id, 1) : null
                  weight                 = (try(iface.ip_sla, null) != null || try(iface.advanced_tracking_options, local.defaults.ndo.tenant_templates.service_device.cluster.interfaces.advanced_tracking_options)) ? try(pbr.weight, local.defaults.ndo.tenant_templates.service_device.cluster.interfaces.pbr.weight) : null
                  additional_tracking_ip = (try(iface.ip_sla, null) != null || try(iface.advanced_tracking_options, local.defaults.ndo.tenant_templates.service_device.cluster.interfaces.advanced_tracking_options)) && try(cluster.device_mode, local.defaults.ndo.tenant_templates.service_device.cluster.device_mode) == "layer3" ? try(pbr.additional_tracking_ip, null) : null
                  is_backup              = try(iface.resilient_hash, local.defaults.ndo.tenant_templates.service_device.cluster.interfaces.resilient_hash) && try(cluster.device_mode, local.defaults.ndo.tenant_templates.service_device.cluster.device_mode) == "layer3" ? try(pbr.backup, false) : null
                }] : []
                fabric_interfaces = try(site.domain_type, local.defaults.ndo.tenant_templates.service_device.cluster.sites.domain_type) == "physical" ? [for fi in try(iface_site.fabric_interfaces, []) : {
                  type    = try(fi.type, local.defaults.ndo.tenant_templates.service_device.cluster.interfaces.fabric_interfaces.type)
                  pod     = try(fi.pod, 1)
                  node    = try(fi.node, null)
                  node_2  = try(fi.node_2, null)
                  port    = try(fi.port, "")
                  module  = try(fi.module, 1)
                  channel = try(fi.channel, null)
                  tag     = try(fi.tag, null)
                  vlan    = try(fi.vlan, null)
                }] : []
                vmm_interfaces = try(site.domain_type, local.defaults.ndo.tenant_templates.service_device.cluster.sites.domain_type) == "vmm" ? [for fi in try(iface_site.fabric_interfaces, []) : {
                  type     = try(fi.type, local.defaults.ndo.tenant_templates.service_device.cluster.interfaces.fabric_interfaces.type)
                  pod      = try(fi.pod, 1)
                  node     = try(fi.node, null)
                  node_2   = try(fi.node_2, null)
                  port     = try(fi.port, "")
                  module   = try(fi.module, 1)
                  channel  = try(fi.channel, null)
                  vmm_name = try(fi.vmm_name, null)
                  vnic     = try(fi.vnic, null)
                }] : []
              }
            ][0]]
          }
        ][0]
      ]
    ]
  ])

}

resource "mso_service_device_cluster_site" "service_device_cluster_site" {
  for_each               = { for site in local.service_device_cluster_sites : site.key => site }
  template_id            = mso_template.service_device_template[each.value.template_name].id
  name                   = each.value.cluster_name
  site_id                = each.value.site_id
  domain_dn              = each.value.domain_name != null ? (each.value.domain_type == "physical" ? "uni/phys-${each.value.domain_name}" : "uni/vmmp-${each.value.vmm_type}/dom-${each.value.domain_name}") : null
  high_availability_mode = each.value.high_availability_mode
  trunking_port          = each.value.domain_type == "vmm" ? each.value.trunking_port : null
  promiscuous_mode       = each.value.domain_type == "vmm" ? each.value.promiscuous_mode : null
  vlan                   = each.value.site_vlan

  dynamic "interfaces" {
    for_each = each.value.interfaces
    content {
      name                = interfaces.value.name
      vlan                = interfaces.value.vlan
      enhanced_lag_policy = interfaces.value.elag
      domain_dn           = interfaces.value.domain_name != null ? "uni/phys-${interfaces.value.domain_name}" : null

      dynamic "fabric_to_device_connectivity" {
        for_each = each.value.domain_type == "physical" ? interfaces.value.fabric_interfaces : []
        content {
          pod_id    = tostring(fabric_to_device_connectivity.value.pod)
          node_id   = fabric_to_device_connectivity.value.type == "vpc" ? [tostring(fabric_to_device_connectivity.value.node), tostring(fabric_to_device_connectivity.value.node_2)] : [tostring(fabric_to_device_connectivity.value.node)]
          path      = fabric_to_device_connectivity.value.type == "port" ? "eth${fabric_to_device_connectivity.value.module}/${fabric_to_device_connectivity.value.port}" : "${fabric_to_device_connectivity.value.channel}${local.defaults.ndo.schemas.templates.application_profiles.endpoint_groups.sites.static_ports.leaf_interface_policy_group_suffix}"
          port_type = fabric_to_device_connectivity.value.type
          tag       = fabric_to_device_connectivity.value.tag
          vlan      = fabric_to_device_connectivity.value.vlan
        }
      }

      dynamic "vm_information" {
        for_each = each.value.domain_type == "vmm" ? interfaces.value.vmm_interfaces : []
        content {
          vm_name   = vm_information.value.vmm_name
          vnic_name = vm_information.value.vnic
          port_type = vm_information.value.type
          pod_id    = vm_information.value.node != null ? tostring(vm_information.value.pod) : null
          path      = vm_information.value.node != null ? (vm_information.value.type == "port" ? "eth${vm_information.value.module}/${vm_information.value.port}" : "${vm_information.value.channel}${local.defaults.ndo.schemas.templates.application_profiles.endpoint_groups.sites.static_ports.leaf_interface_policy_group_suffix}") : null
          node_id   = vm_information.value.node != null ? vm_information.value.type == "vpc" ? [tostring(vm_information.value.node), tostring(vm_information.value.node_2)] : [tostring(vm_information.value.node)] : null
        }
      }

      dynamic "pbr_destinations" {
        for_each = interfaces.value.pbr_destinations
        content {
          ip                     = pbr_destinations.value.ip
          mac                    = pbr_destinations.value.mac
          pod_id                 = pbr_destinations.value.pod_id != null ? tostring(pbr_destinations.value.pod_id) : null
          additional_tracking_ip = pbr_destinations.value.additional_tracking_ip
          weight                 = pbr_destinations.value.weight
          is_backup              = pbr_destinations.value.is_backup
          tag                    = pbr_destinations.value.tag
        }
      }
    }
  }

  depends_on = [
    mso_service_device_cluster.service_device_cluster,
  ]
}