resource "mso_schema" "schema" {
  for_each = { for schema in local.schemas : schema.name => schema }
  name     = each.value.name
  dynamic "template" {
    for_each = { for template in try(each.value.templates, []) : template.name => template }
    content {
      name         = template.value.name
      display_name = template.value.name
      tenant_id    = var.manage_tenants ? mso_tenant.tenant[template.value.tenant].id : data.mso_tenant.tenant[template.value.tenant].id
    }
  }
}

locals {
  template_sites = flatten([
    for schema in local.schemas : [
      for template in try(schema.templates, []) : [
        for site in try(template.sites, []) : {
          key           = "${schema.name}/${template.name}/${site}"
          schema_id     = mso_schema.schema[schema.name].id
          template_name = template.name
          site_name     = site
        }
      ]
    ]
  ])
}

resource "mso_schema_site" "schema_site" {
  for_each            = { for site in local.template_sites : site.key => site }
  schema_id           = each.value.schema_id
  template_name       = each.value.template_name
  site_id             = var.manage_sites ? mso_site.site[each.value.site_name].id : data.mso_site.site[each.value.site_name].id
  undeploy_on_destroy = true
}

locals {
  filter_entries = flatten([
    for schema in local.schemas : [
      for template in try(schema.templates, []) : [
        for filter in try(template.filters, []) : [
          for entry in try(filter.entries, []) : {
            key                  = "${schema.name}/${template.name}/${filter.name}/${entry.name}"
            schema_id            = mso_schema.schema[schema.name].id
            template_name        = template.name
            name                 = "${filter.name}${local.defaults.ndo.schemas.templates.filters.name_suffix}"
            display_name         = "${filter.name}${local.defaults.ndo.schemas.templates.filters.name_suffix}"
            entry_name           = "${entry.name}${local.defaults.ndo.schemas.templates.filters.entries.name_suffix}"
            entry_display_name   = "${entry.name}${local.defaults.ndo.schemas.templates.filters.entries.name_suffix}"
            entry_description    = try(entry.description, "")
            ether_type           = try(entry.ethertype, local.defaults.ndo.schemas.templates.filters.entries.ethertype)
            arp_flag             = "unspecified"
            ip_protocol          = contains(["ip", "ipv4", "ipv6"], try(entry.ethertype, local.defaults.ndo.schemas.templates.filters.entries.ethertype)) ? try(entry.protocol, local.defaults.ndo.schemas.templates.filters.entries.protocol) : "unspecified"
            match_only_fragments = false
            stateful             = try(entry.stateful, local.defaults.ndo.schemas.templates.filters.entries.stateful)
            destination_from     = try(entry.destination_from_port, local.defaults.ndo.schemas.templates.filters.entries.destination_from_port)
            destination_to       = try(entry.destination_to_port, entry.destination_from_port, local.defaults.ndo.schemas.templates.filters.entries.destination_from_port)
            source_from          = try(entry.source_from_port, local.defaults.ndo.schemas.templates.filters.entries.source_from_port)
            source_to            = try(entry.source_to_port, entry.source_from_port, local.defaults.ndo.schemas.templates.filters.entries.source_from_port)
            tcp_session_rules    = ["unspecified"]
          }
        ]
      ]
    ]
  ])
}

resource "mso_schema_template_filter_entry" "schema_template_filter_entry" {
  for_each             = { for entry in local.filter_entries : entry.key => entry }
  schema_id            = each.value.schema_id
  template_name        = each.value.template_name
  name                 = each.value.name
  display_name         = each.value.display_name
  entry_name           = each.value.entry_name
  entry_display_name   = each.value.entry_display_name
  entry_description    = each.value.entry_description
  ether_type           = each.value.ether_type
  arp_flag             = each.value.arp_flag
  ip_protocol          = each.value.ip_protocol
  match_only_fragments = each.value.match_only_fragments
  stateful             = each.value.stateful
  destination_from     = each.value.destination_from
  destination_to       = each.value.destination_to
  source_from          = each.value.source_from
  source_to            = each.value.source_to
  tcp_session_rules    = each.value.tcp_session_rules
}

locals {
  contracts = flatten([
    for schema in local.schemas : [
      for template in try(schema.templates, []) : [
        for contract in try(template.contracts, []) : {
          key           = "${schema.name}/${template.name}/${contract.name}"
          schema_id     = mso_schema.schema[schema.name].id
          template_name = template.name
          contract_name = "${contract.name}${local.defaults.ndo.schemas.templates.contracts.name_suffix}"
          display_name  = "${contract.name}${local.defaults.ndo.schemas.templates.contracts.name_suffix}"
          filter_type   = try(contract.type, local.defaults.ndo.schemas.templates.contracts.type)
          scope         = try(contract.scope, local.defaults.ndo.schemas.templates.contracts.scope)
          directives    = ["none"]
        }
      ]
    ]
  ])
}

resource "mso_schema_template_contract" "schema_template_contract" {
  for_each      = { for contract in local.contracts : contract.key => contract }
  schema_id     = each.value.schema_id
  template_name = each.value.template_name
  contract_name = each.value.contract_name
  display_name  = each.value.display_name
  filter_type   = each.value.filter_type
  scope         = each.value.scope
  directives    = each.value.directives
}

locals {
  contracts_filters = flatten([
    for schema in local.schemas : [
      for template in try(schema.templates, []) : [
        for contract in try(template.contracts, []) : concat([
          for filter in try(contract.filters, []) : {
            key                  = "${schema.name}/${template.name}/${contract.name}/${filter.name}/both"
            schema_id            = mso_schema.schema[schema.name].id
            template_name        = template.name
            contract_name        = "${contract.name}${local.defaults.ndo.schemas.templates.contracts.name_suffix}"
            filter_type          = "bothWay"
            filter_schema_id     = try(filter.schema, null) != null ? mso_schema.schema[filter.schema].id : null
            filter_template_name = try(filter.template, null)
            filter_name          = "${filter.name}${local.defaults.ndo.schemas.templates.filters.name_suffix}"
            directives           = [try(filter.log, local.defaults.ndo.schemas.templates.contracts.filters.log) ? "log" : "none"]
          }
          ],
          [
            for filter in try(contract.provider_to_consumer_filters, []) : {
              key                  = "${schema.name}/${template.name}/${contract.name}/${filter.name}/provider"
              schema_id            = mso_schema.schema[schema.name].id
              template_name        = template.name
              contract_name        = "${contract.name}${local.defaults.ndo.schemas.templates.contracts.name_suffix}"
              filter_type          = "provider_to_consumer"
              filter_schema_id     = try(filter.schema, null) != null ? mso_schema.schema[filter.schema].id : null
              filter_template_name = try(filter.template, null)
              filter_name          = "${filter.name}${local.defaults.ndo.schemas.templates.filters.name_suffix}"
              directives           = [try(filter.log, local.defaults.ndo.schemas.templates.contracts.filters.log) ? "log" : "none"]
            }
          ],
          [
            for filter in try(contract.consumer_to_provider_filters, []) : {
              key                  = "${schema.name}/${template.name}/${contract.name}/${filter.name}/consumer"
              schema_id            = mso_schema.schema[schema.name].id
              template_name        = template.name
              contract_name        = "${contract.name}${local.defaults.ndo.schemas.templates.contracts.name_suffix}"
              filter_type          = "consumer_to_provider"
              filter_schema_id     = try(filter.schema, null) != null ? mso_schema.schema[filter.schema].id : null
              filter_template_name = try(filter.template, null)
              filter_name          = "${filter.name}${local.defaults.ndo.schemas.templates.filters.name_suffix}"
              directives           = [try(filter.log, local.defaults.ndo.schemas.templates.contracts.filters.log) ? "log" : "none"]
            }
        ])
      ]
    ]
  ])
}

resource "mso_schema_template_contract_filter" "schema_template_contract_filter" {
  for_each             = { for filter in local.contracts_filters : filter.key => filter }
  schema_id            = each.value.schema_id
  template_name        = each.value.template_name
  contract_name        = each.value.contract_name
  filter_type          = each.value.filter_type
  filter_schema_id     = each.value.filter_schema_id
  filter_template_name = each.value.filter_template_name
  filter_name          = each.value.filter_name
  directives           = each.value.directives

  depends_on = [mso_schema_template_contract.schema_template_contract]
}

locals {
  vrfs = flatten([
    for schema in local.schemas : [
      for template in try(schema.templates, []) : [
        for vrf in try(template.vrfs, []) : {
          key              = "${schema.name}/${template.name}/${vrf.name}"
          schema_id        = mso_schema.schema[schema.name].id
          template_name    = template.name
          name             = "${vrf.name}${local.defaults.ndo.schemas.templates.vrfs.name_suffix}"
          display_name     = "${vrf.name}${local.defaults.ndo.schemas.templates.vrfs.name_suffix}"
          layer3_multicast = try(vrf.l3_multicast, local.defaults.ndo.schemas.templates.vrfs.l3_multicast)
          vzany            = try(vrf.vzany, local.defaults.ndo.schemas.templates.vrfs.vzany)
        }
      ]
    ]
  ])
}

resource "mso_schema_template_vrf" "schema_template_vrf" {
  for_each         = { for vrf in local.vrfs : vrf.key => vrf }
  schema_id        = each.value.schema_id
  template         = each.value.template_name
  name             = each.value.name
  display_name     = each.value.display_name
  layer3_multicast = each.value.layer3_multicast
  vzany            = each.value.vzany
}

locals {
  vrfs_contracts = flatten([
    for schema in local.schemas : [
      for template in try(schema.templates, []) : [
        for vrf in try(template.vrfs, []) : concat([
          for contract in try(vrf.contracts.consumers, []) : {
            key                    = "${schema.name}/${template.name}/${vrf.name}/${contract.name}/consumer"
            schema_id              = mso_schema.schema[schema.name].id
            template_name          = template.name
            vrf_name               = "${vrf.name}${local.defaults.ndo.schemas.templates.vrfs.name_suffix}"
            contract_name          = "${contract.name}${local.defaults.ndo.schemas.templates.contracts.name_suffix}"
            contract_schema_id     = try(contract.schema, null) != null ? mso_schema.schema[contract.schema].id : null
            contract_template_name = try(contract.template, null)
            relationship_type      = "consumer"
          }
          ],
          [
            for contract in try(vrf.contracts.providers, []) : {
              key                    = "${schema.name}/${template.name}/${vrf.name}/${contract.name}/provider"
              schema_id              = mso_schema.schema[schema.name].id
              template_name          = template.name
              vrf_name               = "${vrf.name}${local.defaults.ndo.schemas.templates.vrfs.name_suffix}"
              contract_name          = "${contract.name}${local.defaults.ndo.schemas.templates.contracts.name_suffix}"
              contract_schema_id     = try(contract.schema, null) != null ? mso_schema.schema[contract.schema].id : null
              contract_template_name = try(contract.template, null)
              relationship_type      = "provider"
            }
        ])
      ]
    ]
  ])
}

resource "mso_schema_template_vrf_contract" "schema_template_vrf_contract" {
  for_each               = { for contract in local.vrfs_contracts : contract.key => contract }
  schema_id              = each.value.schema_id
  template_name          = each.value.template_name
  vrf_name               = each.value.vrf_name
  contract_name          = each.value.contract_name
  contract_schema_id     = each.value.contract_schema_id
  contract_template_name = each.value.contract_template_name
  relationship_type      = each.value.relationship_type

  depends_on = [
    mso_schema_template_vrf.schema_template_vrf,
    mso_schema_template_contract.schema_template_contract,
  ]
}

locals {
  bridge_domains = flatten([
    for schema in local.schemas : [
      for template in try(schema.templates, []) : [
        for bd in try(template.bridge_domains, []) : {
          key                    = "${schema.name}/${template.name}/${bd.name}"
          schema_id              = mso_schema.schema[schema.name].id
          template_name          = template.name
          name                   = "${bd.name}${local.defaults.ndo.schemas.templates.bridge_domains.name_suffix}"
          display_name           = "${bd.name}${local.defaults.ndo.schemas.templates.bridge_domains.name_suffix}"
          vrf_name               = "${bd.vrf.name}${local.defaults.ndo.schemas.templates.vrfs.name_suffix}"
          vrf_schema_id          = try(mso_schema.schema[bd.vrf.schema].id, mso_schema.schema[schema.name].id)
          vrf_template_name      = try(bd.vrf.template, template.name)
          layer2_unknown_unicast = try(bd.l2_unknown_unicast, local.defaults.ndo.schemas.templates.bridge_domains.l2_unknown_unicast, "proxy")
          intersite_bum_traffic  = try(bd.intersite_bum_traffic, local.defaults.ndo.schemas.templates.bridge_domains.intersite_bum_traffic)
          optimize_wan_bandwidth = try(bd.optimize_wan_bandwidth, local.defaults.ndo.schemas.templates.bridge_domains.optimize_wan_bandwidth)
          layer2_stretch         = try(bd.l2_stretch, local.defaults.ndo.schemas.templates.bridge_domains.l2_stretch)
          layer3_multicast       = try(bd.l3_multicast, local.defaults.ndo.schemas.templates.bridge_domains.l3_multicast)
          arp_flooding           = try(bd.arp_flooding, local.defaults.ndo.schemas.templates.bridge_domains.arp_flooding)
          virtual_mac_address    = try(bd.vmac, null) # Not yet implemented in schema
          unicast_routing        = try(bd.unicast_routing, local.defaults.ndo.schemas.templates.bridge_domains.unicast_routing)
          #ipv6_unknown_multicast_flooding = try(bd.unknown_ipv6_multicast, local.defaults.ndo.schemas.templates.bridge_domains.unknown_ipv6_multicast, "flood")               # Not yet implemented in schema
          #multi_destination_flooding      = try(bd.multi_destination_flooding, local.defaults.ndo.schemas.templates.bridge_domains.multi_destination_flooding, "flood_in_bd") # Not yet implemented in schema
          #unknown_multicast_flooding      = try(bd.unknown_ipv4_multicast, local.defaults.ndo.schemas.templates.bridge_domains.unknown_ipv4_multicast, "flood")               # Not yet implemented in schema
        }
      ]
    ]
  ])
}

resource "mso_schema_template_bd" "schema_template_bd" {
  for_each               = { for bd in local.bridge_domains : bd.key => bd }
  schema_id              = each.value.schema_id
  template_name          = each.value.template_name
  name                   = each.value.name
  display_name           = each.value.display_name
  vrf_name               = each.value.vrf_name
  vrf_schema_id          = each.value.vrf_schema_id
  vrf_template_name      = each.value.vrf_template_name
  layer2_unknown_unicast = each.value.layer2_unknown_unicast
  intersite_bum_traffic  = each.value.intersite_bum_traffic
  optimize_wan_bandwidth = each.value.optimize_wan_bandwidth
  layer2_stretch         = each.value.layer2_stretch
  layer3_multicast       = each.value.layer3_multicast
  arp_flooding           = each.value.arp_flooding
  virtual_mac_address    = each.value.virtual_mac_address
  unicast_routing        = each.value.unicast_routing
  #ipv6_unknown_multicast_flooding = each.value.ipv6_unknown_multicast_flooding
  #multi_destination_flooding      = each.value.multi_destination_flooding
  #unknown_multicast_flooding      = each.value.unknown_multicast_flooding
  #  dhcp_policy {
  #    name
  #    version
  #    dhcp_option_policy_name
  #    dhcp_option_policy_version
  #  }
  depends_on = [mso_schema_template_vrf.schema_template_vrf]
}

locals {
  bridge_domains_sites = flatten([
    for schema in local.schemas : [
      for template in try(schema.templates, []) : [
        for bd in try(template.bridge_domains, []) : [
          for site in try(bd.sites, []) : {
            key           = "${schema.name}/${template.name}/${bd.name}/${site.name}"
            schema_id     = mso_schema.schema[schema.name].id
            template_name = template.name
            bd_name       = "${bd.name}${local.defaults.ndo.schemas.templates.bridge_domains.name_suffix}"
            site_id       = var.manage_sites ? mso_site.site[site.name].id : data.mso_site.site[site.name].id
            host_route    = try(site.advertise_host_routes, local.defaults.ndo.schemas.templates.bridge_domains.sites.advertise_host_routes)
            mac           = try(site.mac, local.defaults.ndo.schemas.templates.bridge_domains.sites.mac, "00:22:BD:F8:19:FF") # Not yet implemented in provider
          }
        ]
      ]
    ]
  ])
}

resource "mso_schema_site_bd" "schema_site_bd" {
  for_each      = { for bd in local.bridge_domains_sites : bd.key => bd }
  schema_id     = each.value.schema_id
  template_name = each.value.template_name
  bd_name       = each.value.bd_name
  site_id       = each.value.site_id
  host_route    = each.value.host_route

  depends_on = [mso_schema_template_bd.schema_template_bd]
}

locals {
  bridge_domains_subnets = flatten([
    for schema in local.schemas : [
      for template in try(schema.templates, []) : [
        for bd in try(template.bridge_domains, []) : [
          for subnet in try(bd.subnets, []) : {
            key                = "${schema.name}/${template.name}/${bd.name}/${subnet.ip}"
            schema_id          = mso_schema.schema[schema.name].id
            template_name      = template.name
            bd_name            = "${bd.name}${local.defaults.ndo.schemas.templates.bridge_domains.name_suffix}"
            ip                 = subnet.ip
            scope              = try(subnet.scope, local.defaults.ndo.schemas.templates.bridge_domains.subnets.scope, "private")
            shared             = try(subnet.shared, local.defaults.ndo.schemas.templates.bridge_domains.subnets.shared)
            no_default_gateway = try(subnet.no_default_gateway, local.defaults.ndo.schemas.templates.bridge_domains.subnets.no_default_gateway, false) # Not yet implemented in schema
            querier            = try(subnet.querier, local.defaults.ndo.schemas.templates.bridge_domains.subnets.querier, "disabled")
            primary            = try(subnet.primary, local.defaults.ndo.schemas.templates.bridge_domains.subnets.primary, false) # Not yet implemented in provider
          }
        ]
      ]
    ]
  ])
}

resource "mso_schema_template_bd_subnet" "schema_template_bd_subnet" {
  for_each           = { for subnet in local.bridge_domains_subnets : subnet.key => subnet }
  schema_id          = each.value.schema_id
  template_name      = each.value.template_name
  bd_name            = each.value.bd_name
  ip                 = each.value.ip
  scope              = each.value.scope
  shared             = each.value.shared
  no_default_gateway = each.value.no_default_gateway
  querier            = each.value.querier

  depends_on = [mso_schema_template_bd.schema_template_bd]
}

locals {
  bridge_domains_sites_subnets = flatten([
    for schema in local.schemas : [
      for template in try(schema.templates, []) : [
        for bd in try(template.bridge_domains, []) : [
          for site in try(bd.sites, []) : [
            for subnet in try(site.subnets, []) : {
              key                = "${schema.name}/${template.name}/${bd.name}/${site.name}/${subnet.ip}"
              schema_id          = mso_schema.schema[schema.name].id
              template_name      = template.name
              bd_name            = "${bd.name}${local.defaults.ndo.schemas.templates.bridge_domains.name_suffix}"
              site_id            = var.manage_sites ? mso_site.site[site.name].id : data.mso_site.site[site.name].id
              ip                 = subnet.ip
              scope              = try(subnet.scope, local.defaults.ndo.schemas.templates.bridge_domains.subnets.scope, "private")
              shared             = try(subnet.shared, local.defaults.ndo.schemas.templates.bridge_domains.subnets.shared)
              no_default_gateway = try(subnet.no_default_gateway, local.defaults.ndo.schemas.templates.bridge_domains.subnets.no_default_gateway, false) # Not yet implemented in schema
              querier            = try(subnet.querier, local.defaults.ndo.schemas.templates.bridge_domains.subnets.querier)
              primary            = try(subnet.primary, local.defaults.ndo.schemas.templates.bridge_domains.subnets.primary, false) # Not yet implemented in provider
            }
          ]
        ]
      ]
    ]
  ])
}

resource "mso_schema_site_bd_subnet" "schema_site_bd_subnet" {
  for_each           = { for subnet in local.bridge_domains_sites_subnets : subnet.key => subnet }
  schema_id          = each.value.schema_id
  template_name      = each.value.template_name
  site_id            = each.value.site_id
  bd_name            = each.value.bd_name
  ip                 = each.value.ip
  scope              = each.value.scope
  shared             = each.value.shared
  no_default_gateway = each.value.no_default_gateway
  querier            = each.value.querier

  depends_on = [mso_schema_site_bd.schema_site_bd]
}

locals {
  bridge_domains_sites_l3outs = flatten([
    for schema in local.schemas : [
      for template in try(schema.templates, []) : [
        for bd in try(template.bridge_domains, []) : [
          for site in try(bd.sites, []) : [
            for l3out in try(site.l3outs, []) : {
              key           = "${schema.name}/${template.name}/${bd.name}/${site.name}/${l3out}"
              schema_id     = mso_schema.schema[schema.name].id
              template_name = template.name
              bd_name       = "${bd.name}${local.defaults.ndo.schemas.templates.bridge_domains.name_suffix}"
              site_id       = var.manage_sites ? mso_site.site[site.name].id : data.mso_site.site[site.name].id
              l3out_name    = l3out
            }
          ]
        ]
      ]
    ]
  ])
}

resource "mso_schema_site_bd_l3out" "schema_site_bd_l3out" {
  for_each      = { for l3out in local.bridge_domains_sites_l3outs : l3out.key => l3out }
  schema_id     = each.value.schema_id
  template_name = each.value.template_name
  site_id       = each.value.site_id
  bd_name       = each.value.bd_name
  l3out_name    = each.value.l3out_name

  depends_on = [mso_schema_site_bd.schema_site_bd]
}

locals {
  application_profiles = flatten([
    for schema in local.schemas : [
      for template in try(schema.templates, []) : [
        for ap in try(template.application_profiles, []) : {
          key           = "${schema.name}/${template.name}/${ap.name}"
          schema_id     = mso_schema.schema[schema.name].id
          template_name = template.name
          name          = "${ap.name}${local.defaults.ndo.schemas.templates.application_profiles.name_suffix}"
          display_name  = "${ap.name}${local.defaults.ndo.schemas.templates.application_profiles.name_suffix}"
        }
      ]
    ]
  ])
}

resource "mso_schema_template_anp" "schema_template_anp" {
  for_each     = { for ap in local.application_profiles : ap.key => ap }
  schema_id    = each.value.schema_id
  template     = each.value.template_name
  name         = each.value.name
  display_name = each.value.display_name
}

locals {
  endpoint_groups = flatten([
    for schema in local.schemas : [
      for template in try(schema.templates, []) : [
        for ap in try(template.application_profiles, []) : [
          for epg in try(ap.endpoint_groups, []) : {
            key                        = "${schema.name}/${template.name}/${ap.name}/${epg.name}"
            schema_id                  = mso_schema.schema[schema.name].id
            template_name              = template.name
            anp_name                   = "${ap.name}${local.defaults.ndo.schemas.templates.application_profiles.name_suffix}"
            name                       = "${epg.name}${local.defaults.ndo.schemas.templates.application_profiles.endpoint_groups.name_suffix}"
            bd_name                    = try(epg.bridge_domain.name, null) != null ? "${epg.bridge_domain.name}${local.defaults.ndo.schemas.templates.bridge_domains.name_suffix}" : null
            bd_schema_id               = try(epg.bridge_domain.name, null) != null ? try(mso_schema.schema[epg.bridge_domain.schema].id, mso_schema.schema[schema.name].id) : null
            bd_template_name           = try(epg.bridge_domain.name, null) != null ? try(epg.bridge_domain.template, template.name) : null
            vrf_name                   = try(epg.vrf.name, null) != null ? "${epg.vrf.name}${local.defaults.ndo.schemas.templates.vrfs.name_suffix}" : null
            vrf_schema_id              = try(epg.vrf.name, null) != null ? try(mso_schema.schema[epg.vrf.schema].id, mso_schema.schema[schema.name].id) : null
            vrf_template_name          = try(epg.vrf.name, null) != null ? try(epg.vrf.template, template.name) : null
            useg_epg                   = try(epg.useg, local.defaults.ndo.schemas.templates.application_profiles.endpoint_groups.useg)
            intra_epg                  = try(epg.intra_epg_isolation, local.defaults.ndo.schemas.templates.application_profiles.endpoint_groups.intra_epg_isolation) ? "enforced" : "unenforced"
            intersite_multicast_source = try(epg.intersite_multicast_source, local.defaults.ndo.schemas.templates.application_profiles.endpoint_groups.intersite_multicast_source, false) # Not yet implemented in schema
            proxy_arp                  = try(epg.proxy_arp, local.defaults.ndo.schemas.templates.application_profiles.endpoint_groups.proxy_arp)
            preferred_group            = try(epg.preferred_group, local.defaults.ndo.schemas.templates.application_profiles.endpoint_groups.preferred_group)
            epg_type                   = try(epg.epg_type, local.defaults.ndo.schemas.templates.application_profiles.endpoint_groups.epg_type, "application") # Not yet implemented in schema
            access_type                = try(epg.access_type, null)                                                                                           # Not yet implemented in schema
            deployment_type            = try(epg.deployment_type, null)                                                                                       # Not yet implemented in schema
            service_type               = try(epg.service_type, null)                                                                                          # Not yet implemented in schema
            custom_service_type        = try(epg.service_type, null) == "custom" ? epg.custom_service_type : null                                             # Not yet implemented in schema
          }
        ]
      ]
    ]
  ])
}

resource "mso_schema_template_anp_epg" "schema_template_anp_epg" {
  for_each                   = { for epg in local.endpoint_groups : epg.key => epg }
  schema_id                  = each.value.schema_id
  template_name              = each.value.template_name
  anp_name                   = each.value.anp_name
  name                       = each.value.name
  display_name               = each.value.name
  bd_name                    = each.value.bd_name
  bd_schema_id               = each.value.bd_schema_id
  bd_template_name           = each.value.bd_template_name
  vrf_name                   = each.value.vrf_name
  vrf_schema_id              = each.value.vrf_schema_id
  vrf_template_name          = each.value.vrf_template_name
  useg_epg                   = each.value.useg_epg
  intra_epg                  = each.value.intra_epg
  intersite_multicast_source = each.value.intersite_multicast_source
  proxy_arp                  = each.value.proxy_arp
  preferred_group            = each.value.preferred_group
  epg_type                   = each.value.epg_type
  access_type                = each.value.access_type
  deployment_type            = each.value.deployment_type
  service_type               = each.value.service_type
  custom_service_type        = each.value.custom_service_type

  depends_on = [
    mso_schema_template_bd.schema_template_bd,
    mso_schema_template_anp.schema_template_anp,
  ]
}

locals {
  endpoint_groups_contracts = flatten([
    for schema in local.schemas : [
      for template in try(schema.templates, []) : [
        for ap in try(template.application_profiles, []) : [
          for epg in try(ap.endpoint_groups, []) : concat([
            for contract in try(epg.contracts.consumers, []) : {
              key               = "${schema.name}/${template.name}/${ap.name}/${epg.name}/${contract.name}/consumer"
              schema_id         = mso_schema.schema[schema.name].id
              template_name     = template.name
              anp_name          = "${ap.name}${local.defaults.ndo.schemas.templates.application_profiles.name_suffix}"
              epg_name          = "${epg.name}${local.defaults.ndo.schemas.templates.application_profiles.endpoint_groups.name_suffix}"
              contract_name     = "${contract.name}${local.defaults.ndo.schemas.templates.contracts.name_suffix}"
              relationship_type = "consumer"
            }
            ],
            [
              for contract in try(epg.contracts.providers, []) : {
                key               = "${schema.name}/${template.name}/${ap.name}/${epg.name}/${contract.name}/provider"
                schema_id         = mso_schema.schema[schema.name].id
                template_name     = template.name
                anp_name          = "${ap.name}${local.defaults.ndo.schemas.templates.application_profiles.name_suffix}"
                epg_name          = "${epg.name}${local.defaults.ndo.schemas.templates.application_profiles.endpoint_groups.name_suffix}"
                contract_name     = "${contract.name}${local.defaults.ndo.schemas.templates.contracts.name_suffix}"
                relationship_type = "provider"
              }
          ])
        ]
      ]
    ]
  ])
}

resource "mso_schema_template_anp_epg_contract" "schema_template_anp_epg_contract" {
  for_each          = { for contract in local.endpoint_groups_contracts : contract.key => contract }
  schema_id         = each.value.schema_id
  template_name     = each.value.template_name
  anp_name          = each.value.anp_name
  epg_name          = each.value.epg_name
  contract_name     = each.value.contract_name
  relationship_type = each.value.relationship_type

  depends_on = [
    mso_schema_template_anp_epg.schema_template_anp_epg,
    mso_schema_template_contract.schema_template_contract,
  ]
}

locals {
  endpoint_groups_subnets = flatten([
    for schema in local.schemas : [
      for template in try(schema.templates, []) : [
        for ap in try(template.application_profiles, []) : [
          for epg in try(ap.endpoint_groups, []) : [
            for subnet in try(epg.subnets, []) : {
              key       = "${schema.name}/${template.name}/${ap.name}/${epg.name}/${subnet.ip}"
              schema_id = mso_schema.schema[schema.name].id
              template  = template.name
              anp_name  = "${ap.name}${local.defaults.ndo.schemas.templates.application_profiles.name_suffix}"
              epg_name  = "${epg.name}${local.defaults.ndo.schemas.templates.application_profiles.endpoint_groups.name_suffix}"
              ip        = subnet.ip
              scope     = try(subnet.scope, local.defaults.ndo.schemas.templates.application_profiles.endpoint_groups.subnets.scope)
              shared    = try(subnet.shared, local.defaults.ndo.schemas.templates.application_profiles.endpoint_groups.subnets.shared)
            }
          ]
        ]
      ]
    ]
  ])
}

resource "mso_schema_template_anp_epg_subnet" "schema_template_anp_epg_subnet" {
  for_each  = { for subnet in local.endpoint_groups_subnets : subnet.key => subnet }
  schema_id = each.value.schema_id
  template  = each.value.template
  anp_name  = each.value.anp_name
  epg_name  = each.value.epg_name
  ip        = each.value.ip
  scope     = each.value.scope
  shared    = each.value.shared

  depends_on = [
    mso_schema_template_anp_epg.schema_template_anp_epg,
  ]
}

locals {
  endpoint_groups_sites_subnets = flatten([
    for schema in local.schemas : [
      for template in try(schema.templates, []) : [
        for ap in try(template.application_profiles, []) : [
          for epg in try(ap.endpoint_groups, []) : [
            for site in try(epg.sites, []) : [
              for subnet in try(site.subnets, []) : {
                key                = "${schema.name}/${template.name}/${ap.name}/${epg.name}/${subnet.ip}"
                schema_id          = mso_schema.schema[schema.name].id
                site_id            = var.manage_sites ? mso_site.site[site.name].id : data.mso_site.site[site.name].id
                template_name      = template.name
                anp_name           = "${ap.name}${local.defaults.ndo.schemas.templates.application_profiles.name_suffix}"
                epg_name           = "${epg.name}${local.defaults.ndo.schemas.templates.application_profiles.endpoint_groups.name_suffix}"
                ip                 = subnet.ip
                description        = try(subnet.description, "")
                scope              = try(subnet.scope, local.defaults.ndo.schemas.templates.application_profiles.endpoint_groups.sites.subnets.scope)
                shared             = try(subnet.shared, local.defaults.ndo.schemas.templates.application_profiles.endpoint_groups.sites.subnets.shared)
                no_default_gateway = try(subnet.no_default_gateway, local.defaults.ndo.schemas.templates.application_profiles.endpoint_groups.sites.subnets.no_default_gateway)
              }
            ]
          ]
        ]
      ]
    ]
  ])
}

resource "mso_schema_site_anp_epg_subnet" "schema_site_anp_epg_subnet" {
  for_each           = { for subnet in local.endpoint_groups_sites_subnets : subnet.key => subnet }
  schema_id          = each.value.schema_id
  site_id            = each.value.site_id
  template_name      = each.value.template_name
  anp_name           = each.value.anp_name
  epg_name           = each.value.epg_name
  ip                 = each.value.ip
  description        = each.value.description
  scope              = each.value.scope
  shared             = each.value.shared
  no_default_gateway = each.value.no_default_gateway

  depends_on = [
    mso_schema_template_anp_epg_subnet.schema_template_anp_epg_subnet,
  ]
}

#resource "mso_schema_template_anp_epg_useg_attr" "useg_attr" {
#}

#resource "mso_schema_site_anp_epg_domain" "domain" {
#}

#resource "mso_schema_site_anp_epg_static_leaf" "static_leaf" {
#}

#resource "mso_schema_site_anp_epg_static_port" "static_port" {
#}
