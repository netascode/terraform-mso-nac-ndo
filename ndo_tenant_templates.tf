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

  depends_on = [
    mso_schema_template_anp_epg.schema_template_anp_epg,
    mso_schema_template_external_epg.schema_template_external_epg
  ]
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
          interface_type            = try(iface.interface_type, "bd")
          redirect                  = try(iface.interface_type, "bd") != "l3out" && (try(iface.ip_sla, null) != null || try(iface.redirect, local.defaults.ndo.tenant_templates.service_device.cluster.interfaces.redirect))
          bd_uuid_key               = try(iface.interface_type, "bd") == "bd" ? "${try(iface.schema, "")}/${try(iface.template, "")}/${try(iface.bridge_domain, "")}" : null
          external_epg_uuid_key     = try(iface.interface_type, "bd") == "l3out" ? "${try(iface.schema, "")}/${try(iface.template, "")}/${try(iface.external_epg, "")}" : null
          ipsla_key                 = try(iface.ip_sla, null) != null ? "${try(iface.ip_sla.template, template.name)}/${try(iface.ip_sla.name, "")}" : null
          advanced_tracking_options = try(iface.ip_sla, null) != null || try(iface.advanced_tracking_options, local.defaults.ndo.tenant_templates.service_device.cluster.interfaces.advanced_tracking_options)
          preferred_group           = try(iface.preferred_group, local.defaults.ndo.tenant_templates.service_device.cluster.interfaces.preferred_group)
          rewrite_source_mac        = try(iface.rewrite_source_mac, local.defaults.ndo.tenant_templates.service_device.cluster.interfaces.rewrite_source_mac)
          anycast                   = try(iface.anycast, local.defaults.ndo.tenant_templates.service_device.cluster.interfaces.anycast)
          config_static_mac         = (try(iface.ip_sla, null) != null || try(iface.advanced_tracking_options, local.defaults.ndo.tenant_templates.service_device.cluster.interfaces.advanced_tracking_options)) ? try(iface.static_mac, local.defaults.ndo.tenant_templates.service_device.cluster.interfaces.config_static_mac) : null
          is_backup_redirect_ip     = (try(iface.ip_sla, null) != null || try(iface.advanced_tracking_options, local.defaults.ndo.tenant_templates.service_device.cluster.interfaces.advanced_tracking_options)) ? try(iface.backup_redirect_ip, local.defaults.ndo.tenant_templates.service_device.cluster.interfaces.backup_redirect_ip) : null
          load_balance_hashing      = try(iface.load_balance_hashing, local.defaults.ndo.tenant_templates.service_device.cluster.interfaces.load_balance_hashing)
          pod_aware_redirection     = try(iface.pod_aware_redirection, local.defaults.ndo.tenant_templates.service_device.cluster.interfaces.pod_aware_redirection)
          resilient_hashing         = (try(iface.ip_sla, null) != null || try(iface.advanced_tracking_options, local.defaults.ndo.tenant_templates.service_device.cluster.interfaces.advanced_tracking_options)) ? try(iface.resilient_hash, local.defaults.ndo.tenant_templates.service_device.cluster.interfaces.resilient_hash) : null
          tag_based_sorting         = (try(iface.ip_sla, null) != null || try(iface.advanced_tracking_options, local.defaults.ndo.tenant_templates.service_device.cluster.interfaces.advanced_tracking_options)) ? try(iface.tag_based_sorting, local.defaults.ndo.tenant_templates.service_device.cluster.interfaces.tag_based_sorting) : null
          min_threshold             = (try(iface.ip_sla, null) != null || try(iface.advanced_tracking_options, local.defaults.ndo.tenant_templates.service_device.cluster.interfaces.advanced_tracking_options)) ? try(iface.threshold.min_threshold, local.defaults.ndo.tenant_templates.service_device.cluster.interfaces.threshold.min_threshold) : null
          max_threshold             = (try(iface.ip_sla, null) != null || try(iface.advanced_tracking_options, local.defaults.ndo.tenant_templates.service_device.cluster.interfaces.advanced_tracking_options)) ? try(iface.threshold.max_threshold, local.defaults.ndo.tenant_templates.service_device.cluster.interfaces.threshold.max_threshold) : null
          threshold_down_action     = (try(iface.ip_sla, null) != null || try(iface.advanced_tracking_options, local.defaults.ndo.tenant_templates.service_device.cluster.interfaces.advanced_tracking_options)) ? try(iface.threshold.down_action, local.defaults.ndo.tenant_templates.service_device.cluster.interfaces.threshold.down_action) : null
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



locals {
  service_device_cluster_sites = flatten([
    for template in local.service_device_templates : [
      for cluster in try(template.cluster, []) : [
        for site_name in try(template.sites, []) : {
          key                    = "service_device/${template.name}/${cluster.name}/${site_name}"
          template_name          = template.name
          cluster_name           = cluster.name
          site_name              = site_name
          site_id                = var.manage_sites && local.ndo_platform_version != "4.1" ? mso_site.site[site_name].id : data.mso_site.tenant_templates_site[site_name].id
          device_mode            = try(cluster.device_mode, local.defaults.ndo.tenant_templates.service_device.cluster.device_mode)
          domain_type            = try((([for s in try(cluster.sites, []) : s if s.name == site_name])[0]).domain_type, local.defaults.ndo.tenant_templates.service_device.cluster.sites.domain_type)
          domain_name            = try((([for s in try(cluster.sites, []) : s if s.name == site_name])[0]).domain_name, "")
          vmm_type               = try((([for s in try(cluster.sites, []) : s if s.name == site_name])[0]).vmm_type, local.defaults.ndo.tenant_templates.service_device.cluster.sites.vmm_type)
          trunking_port          = try((([for s in try(cluster.sites, []) : s if s.name == site_name])[0]).trunking_port, local.defaults.ndo.tenant_templates.service_device.cluster.sites.trunking_port)
          promiscuous_mode       = try((([for s in try(cluster.sites, []) : s if s.name == site_name])[0]).promiscuous_mode, local.defaults.ndo.tenant_templates.service_device.cluster.sites.promiscuous_mode)
          high_availability_mode = contains(["layer2", "layer1"], try(cluster.device_mode, local.defaults.ndo.tenant_templates.service_device.cluster.device_mode)) ? try((([for s in try(cluster.sites, []) : s if s.name == site_name])[0]).high_availability_mode, local.defaults.ndo.tenant_templates.service_device.cluster.sites.high_availability_mode) : null
          interfaces = [for iface in try(cluster.interfaces, []) : {
            name = iface.name
            vlan = try((([for s in try(iface.sites, []) : s if s.name == site_name])[0]).vlan, null)
            elag = try((([for s in try(iface.sites, []) : s if s.name == site_name])[0]).elag, "")
            pbr_destinations = (try(iface.ip_sla, null) != null || try(iface.redirect, local.defaults.ndo.tenant_templates.service_device.cluster.interfaces.redirect)) && try(iface.interface_type, "bd") != "l3out" ? [for pbr in try((([for s in try(iface.sites, []) : s if s.name == site_name])[0]).pbr_destinations, []) : {
              ip                     = try(pbr.ip, null)
              mac                    = try(pbr.mac, null)
              tag                    = try(pbr.tag, null)
              pod_id                 = try(iface.pod_aware_redirection, local.defaults.ndo.tenant_templates.service_device.cluster.interfaces.pod_aware_redirection) ? try(pbr.pod_id, 1) : null
              weight                 = (try(iface.ip_sla, null) != null || try(iface.advanced_tracking_options, local.defaults.ndo.tenant_templates.service_device.cluster.interfaces.advanced_tracking_options)) ? try(pbr.weight, local.defaults.ndo.tenant_templates.service_device.cluster.interfaces.pbr.weight) : null
              additional_tracking_ip = (try(iface.ip_sla, null) != null || try(iface.advanced_tracking_options, local.defaults.ndo.tenant_templates.service_device.cluster.interfaces.advanced_tracking_options)) && try(cluster.device_mode, local.defaults.ndo.tenant_templates.service_device.cluster.device_mode) == "layer3" ? try(pbr.additional_tracking_ip, null) : null
              is_backup              = try(iface.resilient_hash, local.defaults.ndo.tenant_templates.service_device.cluster.interfaces.resilient_hash) && try(cluster.device_mode, local.defaults.ndo.tenant_templates.service_device.cluster.device_mode) == "layer3" ? try(pbr.backup, false) : null
            }] : []
            fabric_interfaces = try((([for s in try(cluster.sites, []) : s if s.name == site_name])[0]).domain_type, local.defaults.ndo.tenant_templates.service_device.cluster.sites.domain_type) == "physical" ? [for fi in try((([for s in try(iface.sites, []) : s if s.name == site_name])[0]).fabric_interfaces, []) : {
              type    = try(fi.type, local.defaults.ndo.tenant_templates.service_device.cluster.interfaces.fabric_interfaces.type)
              pod     = try(fi.pod, 1)
              node    = try(fi.node, null)
              node_2  = try(fi.node_2, null)
              port    = try(fi.port, null)
              module  = try(fi.module, 1)
              channel = try(fi.channel, null)
              tag     = try(fi.tag, null)
              vlan    = try(fi.vlan, null)
            }] : []
            vmm_interfaces = try((([for s in try(cluster.sites, []) : s if s.name == site_name])[0]).domain_type, local.defaults.ndo.tenant_templates.service_device.cluster.sites.domain_type) == "vmm" ? [for fi in try((([for s in try(iface.sites, []) : s if s.name == site_name])[0]).fabric_interfaces, []) : {
              type     = try(fi.type, local.defaults.ndo.tenant_templates.service_device.cluster.interfaces.fabric_interfaces.type)
              pod      = try(fi.pod, 1)
              node     = try(fi.node, null)
              node_2   = try(fi.node_2, null)
              port     = try(fi.port, null)
              module   = try(fi.module, 1)
              channel  = try(fi.channel, null)
              vmm_name = try(fi.vmm_name, null)
              vnic     = try(fi.vnic, null)
            }] : []
          }]
        }
      ]
    ]
  ])

  service_device_cluster_site_payloads = {
    for template in local.service_device_templates : template.name => {
      patch = concat([{
        op   = "replace"
        path = "/deviceTemplate/template/devices"
        value = [
          for cluster in [for c in local.service_device_clusters : c if c.template_name == template.name] :
          merge(
            {
              name             = cluster.name
              deviceLocation   = "onPremise"
              deviceType       = cluster.device_type
              deviceMode       = cluster.device_mode
              connectivityMode = length(cluster.interfaces) == 0 ? "" : (length(cluster.interfaces) == 1 && cluster.device_mode == "layer3" ? "oneArm" : (length(cluster.interfaces) == 2 ? "twoArm" : "other"))
              interfaces = [for iface in cluster.interfaces : merge(concat(
                [{
                  name                = iface.name
                  deviceInterfaceType = iface.interface_type
                  redirect            = iface.redirect
                }],
                iface.bd_uuid_key != null ? [{
                  bdRef = !var.manage_schemas || (var.manage_schemas && !contains(local.managed_schemas, split("/", iface.bd_uuid_key)[0])) ? data.mso_schema_template_bd.service_device_bd[iface.bd_uuid_key].uuid : mso_schema_template_bd.schema_template_bd["${split("/", iface.bd_uuid_key)[0]}/${split("/", iface.bd_uuid_key)[1]}/${split("/", iface.bd_uuid_key)[2]}"].uuid
                }] : [],
                iface.external_epg_uuid_key != null ? [{
                  externalEpgRef = !var.manage_schemas || (var.manage_schemas && !contains(local.managed_schemas, split("/", iface.external_epg_uuid_key)[0])) ? data.mso_schema_template_external_epg.service_device_external_epg[iface.external_epg_uuid_key].uuid : mso_schema_template_external_epg.schema_template_external_epg["${split("/", iface.external_epg_uuid_key)[0]}/${split("/", iface.external_epg_uuid_key)[1]}/${split("/", iface.external_epg_uuid_key)[2]}"].uuid
                }] : [],
                iface.ipsla_key != null ? [{
                  ipslaMonitoringRef = mso_tenant_policies_ipsla_monitoring_policy.tenant_policies_ipsla_monitoring_policy[split("/", iface.ipsla_key)[1]].uuid
                }] : [],
                (iface.advanced_tracking_options || iface.preferred_group || iface.rewrite_source_mac || iface.anycast || iface.redirect) ? [{
                  isAdvancedIntfConfig = true
                  advancedIntfConfig = merge(concat(
                    [{
                      preferredGroup          = iface.preferred_group
                      advancedTrackingOptions = iface.advanced_tracking_options
                    }],
                    iface.redirect ? [{
                      loadBalanceHashing  = iface.load_balance_hashing
                      podAwareRedirection = iface.pod_aware_redirection
                      anycast             = iface.anycast
                      rewriteSourceMac    = iface.rewrite_source_mac
                    }] : [],
                    iface.advanced_tracking_options ? [{
                      configStaticMac  = iface.config_static_mac
                      tag              = iface.tag_based_sorting
                      resilientHashing = iface.resilient_hashing
                    }] : [],
                    iface.advanced_tracking_options && iface.resilient_hashing == true ? [{
                      isBackupRedirectIP = iface.is_backup_redirect_ip
                    }] : [],
                    iface.advanced_tracking_options && iface.min_threshold != null ? [{
                      thresholdForRedirectDestination = true
                      thresholdForRedirect = {
                        minThreshold        = iface.min_threshold
                        maxThreshold        = iface.max_threshold
                        thresholdDownAction = iface.threshold_down_action
                      }
                    }] : [],
                  )...)
                }] : [],
              )...)]
            }
          )
        ]
        }], [{
        op   = "replace"
        path = "/deviceTemplate/sites"
        value = [
          for site_name in try(template.sites, []) :
          {
            siteId = var.manage_sites && local.ndo_platform_version != "4.1" ? mso_site.site[site_name].id : data.mso_site.tenant_templates_site[site_name].id
            devices = [
              for site in [for s in local.service_device_cluster_sites : s if s.template_name == template.name && s.site_name == site_name] :
              merge(
                {
                  name             = site.cluster_name
                  isPhysicalDomain = site.domain_type == "physical" || contains(["layer2", "layer1"], site.device_mode)
                  domainDn         = site.domain_type == "physical" ? "uni/phys-${site.domain_name}" : "uni/vmmp-${site.vmm_type}/dom-${site.domain_name}"
                },
                contains(["layer2", "layer1"], site.device_mode) ? { highAvailabilityMode = site.high_availability_mode } : {},
                site.domain_type == "vmm" ? {
                  trunkingPort     = site.trunking_port
                  promiscuous_mode = site.promiscuous_mode
                } : {},
                {
                  interfaces = [for iface in site.interfaces : merge(
                    { name = iface.name },
                    iface.vlan != null && site.high_availability_mode != "activeActive" ? { vlan = iface.vlan } : {},
                    length(iface.pbr_destinations) > 0 ? {
                      pbrDestinations = [for pbr in iface.pbr_destinations : merge(
                        pbr.ip != null ? { ip = pbr.ip } : {},
                        pbr.mac != null ? { mac = pbr.mac } : {},
                        pbr.tag != null ? { tag = pbr.tag } : {},
                        pbr.pod_id != null ? { podID = tostring(pbr.pod_id) } : {},
                        pbr.weight != null ? { weight = pbr.weight } : {},
                        pbr.additional_tracking_ip != null ? { additionalTrackingIP = pbr.additional_tracking_ip } : {},
                        pbr.is_backup != null ? { isBackUp = pbr.is_backup } : {},
                      )]
                    } : {},
                    site.domain_type == "physical" && length(iface.fabric_interfaces) > 0 ? {
                      fabricToDeviceConnectivity = [for fi in iface.fabric_interfaces : merge(
                        {
                          portType = fi.type
                          podID    = tostring(fi.pod)
                        },
                        fi.tag != null && contains(["layer2", "layer1"], site.device_mode) ? { tag = fi.tag } : {},
                        fi.vlan != null && site.high_availability_mode == "activeActive" ? { vlan = fi.vlan } : {},
                        fi.type == "port" ? {
                          path   = "topology/pod-${fi.pod}/paths-${fi.node}/pathep-[eth${fi.module}/${fi.port}]"
                          nodeID = tostring(fi.node)
                        } : {},
                        fi.type == "vpc" ? {
                          path   = "topology/pod-${fi.pod}/protpaths-${fi.node}-${fi.node_2}/pathep-[${fi.channel}${local.defaults.ndo.schemas.templates.application_profiles.endpoint_groups.sites.static_ports.leaf_interface_policy_group_suffix}]"
                          nodeID = "${fi.node},${fi.node_2}"
                        } : {},
                        fi.type == "dpc" ? {
                          path   = "topology/pod-${fi.pod}/paths-${fi.node}/pathep-[${fi.channel}${local.defaults.ndo.schemas.templates.application_profiles.endpoint_groups.sites.static_ports.leaf_interface_policy_group_suffix}]"
                          nodeID = tostring(fi.node)
                        } : {},
                      )]
                    } : {},
                    site.domain_type == "vmm" ? merge(
                      { enhancedLagPolicy = iface.elag },
                      length(iface.vmm_interfaces) > 0 ? {
                        vmmIntfInfo = [for fi in iface.vmm_interfaces : merge(
                          {
                            vmName   = fi.vmm_name
                            vNicName = fi.vnic
                            portType = fi.type
                            podID    = tostring(fi.pod)
                          },
                          fi.type == "port" ? {
                            path   = "topology/pod-${fi.pod}/paths-${fi.node}/pathep-[eth${fi.module}/${fi.port}]"
                            nodeID = tostring(fi.node)
                          } : {},
                          fi.type == "vpc" ? {
                            path   = "topology/pod-${fi.pod}/protpaths-${fi.node}-${fi.node_2}/pathep-[${fi.channel}${local.defaults.ndo.schemas.templates.application_profiles.endpoint_groups.sites.static_ports.leaf_interface_policy_group_suffix}]"
                            nodeID = "${fi.node},${fi.node_2}"
                          } : {},
                          fi.type == "dpc" ? {
                            path   = "topology/pod-${fi.pod}/paths-${fi.node}/pathep-[${fi.channel}${local.defaults.ndo.schemas.templates.application_profiles.endpoint_groups.sites.static_ports.leaf_interface_policy_group_suffix}]"
                            nodeID = tostring(fi.node)
                          } : {},
                        )]
                      } : {},
                    ) : {},
                  )]
                }
              )
            ]
          }
        ]
      }])
    } if length(try(template.sites, [])) > 0 || length(try(template.cluster, [])) > 0
  }
}

resource "mso_rest" "service_device_cluster_site" {
  for_each = local.service_device_cluster_site_payloads
  path     = "api/v1/templates/${mso_template.service_device_template[each.key].id}"
  method   = "PATCH"
  payload  = jsonencode(each.value.patch)

  depends_on = [
    mso_schema_template_bd.schema_template_bd,
    mso_schema_template_external_epg.schema_template_external_epg,
    mso_tenant_policies_ipsla_monitoring_policy.tenant_policies_ipsla_monitoring_policy,
  ]
}