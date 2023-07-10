locals {
  template_tenants = flatten(distinct([
    for schema in local.schemas : [
      for template in try(schema.templates, []) : template.tenant
    ]
  ]))
  managed_schemas = [for schema in local.schemas : schema.name]
  template_schemas = distinct(flatten([
    for schema in local.schemas : [
      for template in try(schema.templates, []) : [
        [for l3out in try(template.l3outs, []) : try([l3out.vrf.schema], [])],
        [for bd in try(template.bridge_domains, []) : try([bd.vrf.schema], [])],
        [for eepg in try(template.external_endpoint_groups, []) : [
          [try([eepg.vrf.schema], [])],
          [try([eepg.l3out.schema], [])],
          [try([eepg.application_profile.schema], [])],
          [for consumer in try(eepg.contracts.consumers, []) : try([consumer.schema], [])],
          [for provider in try(eepg.contracts.providers, []) : try([provider.schema], [])],
          [for site in try(eepg.sites, []) : try([site.l3out.schema], [])]
        ]],
        [for vrf in try(template.vrfs, []) : [
          [for consumer in try(vrf.contracts.consumers, []) : try([consumer.schema], [])],
          [for provider in try(vrf.contracts.providers, []) : try([provider.schema], [])],
        ]],
        [for ap in try(template.application_profiles, []) : [
          [for epg in try(ap.endpoint_groups, []) : [
            [try([epg.bridge_domain.schema], [])],
            [try([epg.vrf.schema], [])],
            [for consumer in try(epg.contracts.consumers, []) : try([consumer.schema], [])],
            [for provider in try(epg.contracts.providers, []) : try([provider.schema], [])]
          ]]
        ]],
        [for contract in try(template.contracts, []) : [
          [for filter in try(contract.filters, []) : try([filter.schema], [])],
          [for filter in try(contract.provider_to_consumer_filters, []) : try([filter.schema], [])],
          [for filter in try(contract.consumer_to_provider_filters, []) : try([filter.schema], [])],
          [try([contract.service_graph.schema], [])],
          [for node in try(contract.service_graph.nodes, []) : [
            [try([node.consumer.schema], [])],
            [try([node.provider.schema], [])]
          ]]
        ]]
      ]
    ]
  ]))
}

data "mso_tenant" "template_tenant" {
  for_each = toset([for tenant in local.template_tenants : tenant if !var.manage_tenants && var.manage_schemas])
  name     = each.value
}

data "mso_schema" "template_schema" {
  for_each = toset([for schema in local.template_schemas : schema if !contains(local.managed_schemas, schema) && var.manage_schemas])
  name     = each.value
}

resource "mso_schema" "schema" {
  for_each = { for schema in local.schemas : schema.name => schema }
  name     = each.value.name
  dynamic "template" {
    for_each = { for template in try(each.value.templates, []) : template.name => template }
    content {
      name         = template.value.name
      display_name = template.value.name
      tenant_id    = var.manage_tenants ? mso_tenant.tenant[template.value.tenant].id : data.mso_tenant.template_tenant[template.value.tenant].id
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

data "mso_site" "template_site" {
  for_each = toset(distinct([for site in local.template_sites : site.site_name if !var.manage_sites && var.manage_schemas]))
  name     = each.value
}

resource "mso_schema_site" "schema_site" {
  for_each            = { for site in local.template_sites : site.key => site }
  schema_id           = each.value.schema_id
  template_name       = each.value.template_name
  site_id             = var.manage_sites ? mso_site.site[each.value.site_name].id : data.mso_site.template_site[each.value.site_name].id
  undeploy_on_destroy = true

  depends_on = [mso_schema.schema]
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
  contracts_sites = flatten([
    for schema in local.schemas : [
      for template in try(schema.templates, []) : [
        for contract in try(template.contracts, []) : [
          for site in try(template.sites, []) : {
            key       = "${schema.name}/${template.name}/${contract.name}/${site}"
            schema_id = mso_schema.schema[schema.name].id
            patch = [{
              op   = "add"
              path = "/sites/${var.manage_sites ? mso_site.site[site].id : data.mso_site.template_site[site].id}-${template.name}/contracts/-"
              value = {
                contractRef = {
                  contractName = "${contract.name}${local.defaults.ndo.schemas.templates.contracts.name_suffix}"
                  schemaId     = mso_schema.schema[schema.name].id
                  templateName = template.name
                }
              }
            }]
          }
        ]
      ]
    ]
  ])
}

resource "mso_rest" "schema_site_contract" {
  for_each = { for contract in local.contracts_sites : contract.key => contract }
  path     = "api/v1/schemas/${each.value.schema_id}?validate=false"
  method   = "PATCH"
  payload  = jsonencode(each.value.patch)

  depends_on = [
    mso_schema_site.schema_site,
    mso_schema_template_contract.schema_template_contract,
  ]
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
            filter_schema_id     = try(filter.schema, null) != null ? try(mso_schema.schema[filter.schema].id, data.mso_schema.template_schema[filter.schema].id) : null
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
              filter_schema_id     = try(filter.schema, null) != null ? try(mso_schema.schema[filter.schema].id, data.mso_schema.template_schema[filter.schema].id) : null
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
              filter_schema_id     = try(filter.schema, null) != null ? try(mso_schema.schema[filter.schema].id, data.mso_schema.template_schema[filter.schema].id) : null
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

  depends_on = [
    mso_schema_template_contract.schema_template_contract,
    mso_schema_template_filter_entry.schema_template_filter_entry
  ]
}

locals {
  contracts_service_graphs_sites = flatten([
    for schema in local.schemas : [
      for template in try(schema.templates, []) : [
        for contract in try(template.contracts, []) : [
          for node in try(contract.service_graph.nodes, []) : [
            for site in try(node.provider.sites, []) : {
              key                         = "${schema.name}/${template.name}/${contract.name}/${node.name}/${site.name}"
              schema_id                   = mso_schema.schema[schema.name].id
              site_id                     = var.manage_sites ? mso_site.site[site.name].id : data.mso_site.template_site[site.name].id
              template_name               = template.name
              contract_name               = "${contract.name}${local.defaults.ndo.schemas.templates.contracts.name_suffix}"
              service_graph_name          = "${contract.service_graph.name}${local.defaults.ndo.schemas.templates.service_graphs.name_suffix}"
              service_graph_schema_id     = try(contract.service_graph.schema, null) != null ? try(mso_schema.schema[contract.service_graph.schema].id, data.mso_schema.template_schema[contract.service_graph.schema].id) : null
              service_graph_template_name = try(contract.service_graph.template, null)
              node_relationship = [{
                key                                       = "${node.provider.bridge_domain}/${node.consumer.bridge_domain}/${site.logical_interface}/${site.redirect_policy}/${[for s in try(node.consumer.sites, []) : s if s.name == site.name][0].logical_interface}/${[for s in try(node.consumer.sites, []) : s if s.name == site.name][0].redirect_policy}"
                provider_connector_bd_name                = node.provider.bridge_domain
                provider_connector_bd_schema_id           = try(node.provider.schema, null) != null ? try(mso_schema.schema[node.provider.schema].id, data.mso_schema.template_schema[node.provider.schema].id) : null
                provider_connector_bd_template_name       = try(node.provider.template, null)
                consumer_connector_bd_name                = node.consumer.bridge_domain
                consumer_connector_bd_schema_id           = try(node.consumer.schema, null) != null ? try(mso_schema.schema[node.consumer.schema].id, data.mso_schema.template_schema[node.consumer.schema].id) : null
                consumer_connector_bd_template_name       = try(node.consumer.template, null)
                provider_connector_cluster_interface      = "${site.logical_interface}${local.defaults.ndo.schemas.templates.service_graphs.logical_interface_name_suffix}"
                consumer_connector_cluster_interface      = "${[for s in try(node.consumer.sites, []) : s if s.name == site.name][0].logical_interface}${local.defaults.ndo.schemas.templates.service_graphs.logical_interface_name_suffix}"
                provider_connector_redirect_policy_tenant = try(site.tenant, template.tenant)
                provider_connector_redirect_policy        = "${site.redirect_policy}${local.defaults.ndo.schemas.templates.service_graphs.redirect_policy_name_suffix}"
                consumer_connector_redirect_policy_tenant = try([for s in try(node.consumer.sites, []) : s if s.name == site.name][0].tenant, template.tenant)
                consumer_connector_redirect_policy        = "${[for s in try(node.consumer.sites, []) : s if s.name == site.name][0].redirect_policy}${local.defaults.ndo.schemas.templates.service_graphs.redirect_policy_name_suffix}"
              }]
            }
          ]
        ]
      ]
    ]
  ])
}

resource "mso_schema_template_contract_service_graph" "schema_template_contract_service_graph" {
  for_each                    = { for sg in local.contracts_service_graphs_sites : sg.key => sg }
  schema_id                   = each.value.schema_id
  site_id                     = each.value.site_id
  template_name               = each.value.template_name
  contract_name               = each.value.contract_name
  service_graph_name          = each.value.service_graph_name
  service_graph_schema_id     = each.value.service_graph_schema_id
  service_graph_template_name = each.value.service_graph_template_name

  dynamic "node_relationship" {
    for_each = { for node_relationship in try(each.value.node_relationship, []) : node_relationship.key => node_relationship }
    content {
      provider_connector_bd_name                = node_relationship.value.provider_connector_bd_name
      provider_connector_bd_schema_id           = node_relationship.value.provider_connector_bd_schema_id
      provider_connector_bd_template_name       = node_relationship.value.provider_connector_bd_template_name
      consumer_connector_bd_name                = node_relationship.value.consumer_connector_bd_name
      consumer_connector_bd_schema_id           = node_relationship.value.consumer_connector_bd_schema_id
      consumer_connector_bd_template_name       = node_relationship.value.consumer_connector_bd_template_name
      provider_connector_cluster_interface      = node_relationship.value.provider_connector_cluster_interface
      consumer_connector_cluster_interface      = node_relationship.value.consumer_connector_cluster_interface
      provider_connector_redirect_policy_tenant = node_relationship.value.provider_connector_redirect_policy_tenant
      provider_connector_redirect_policy        = node_relationship.value.provider_connector_redirect_policy
      consumer_connector_redirect_policy_tenant = node_relationship.value.consumer_connector_redirect_policy_tenant
      consumer_connector_redirect_policy        = node_relationship.value.consumer_connector_redirect_policy
    }
  }

  depends_on = [
    mso_schema_template_contract.schema_template_contract,
    mso_schema_template_service_graph.schema_template_service_graph,
    mso_rest.schema_site_contract,
    mso_schema_template_anp_epg_contract.schema_template_anp_epg_contract,
    mso_schema_template_external_epg_contract.schema_template_external_epg_contract,
    mso_schema_template_vrf_contract.schema_template_vrf_contract,
  ]
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
  vrfs_sites = flatten([
    for schema in local.schemas : [
      for template in try(schema.templates, []) : [
        for vrf in try(template.vrfs, []) : [
          for site in try(vrf.sites, []) : {
            key           = "${schema.name}/${template.name}/${vrf.name}/${site.name}"
            schema_id     = mso_schema.schema[schema.name].id
            site_id       = var.manage_sites ? mso_site.site[site.name].id : data.mso_site.template_site[site.name].id
            template_name = template.name
            vrf_name      = "${vrf.name}${local.defaults.ndo.schemas.templates.vrfs.name_suffix}"
          }
        ]
      ]
    ]
  ])
}

resource "mso_schema_site_vrf" "schema_site_vrf" {
  for_each      = { for site in local.vrfs_sites : site.key => site }
  schema_id     = each.value.schema_id
  site_id       = each.value.site_id
  template_name = each.value.template_name
  vrf_name      = each.value.vrf_name

  depends_on = [mso_schema_template_vrf.schema_template_vrf]
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
            contract_schema_id     = try(contract.schema, null) != null ? try(mso_schema.schema[contract.schema].id, data.mso_schema.template_schema[contract.schema].id) : null
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
              contract_schema_id     = try(contract.schema, null) != null ? try(mso_schema.schema[contract.schema].id, data.mso_schema.template_schema[contract.schema].id) : null
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
  vrfs_sites_regions = flatten([
    for schema in local.schemas : [
      for template in try(schema.templates, []) : [
        for vrf in try(template.vrfs, []) : [
          for site in try(vrf.sites, []) : [
            for region in try(site.regions, []) : {
              key                = "${schema.name}/${template.name}/${vrf.name}/${site.name}/${region.name}"
              schema_id          = mso_schema.schema[schema.name].id
              site_id            = var.manage_sites ? mso_site.site[site.name].id : data.mso_site.template_site[site.name].id
              template_name      = template.name
              vrf_name           = "${vrf.name}${local.defaults.ndo.schemas.templates.vrfs.name_suffix}"
              region_name        = region.name
              vpn_gateway        = try(region.vpn_gateway, local.defaults.ndo.schemas.templates.vrfs.sites.regions.vpn_gateway)
              hub_network_enable = try(region.hub_network, local.defaults.ndo.schemas.templates.vrfs.sites.regions.hub_network)
              hub_network = try(region.hub_network, local.defaults.ndo.schemas.templates.vrfs.sites.regions.hub_network) ? {
                name        = region.hub_network_name
                tenant_name = region.hub_network_tenant
              } : null
              cidr = [for cidr in try(region.cidrs, []) : {
                cidr_ip = cidr.ip
                primary = true
                subnet = [for subnet in try(cidr.subnets, []) : {
                  ip   = subnet.ip
                  zone = try(subnet.zone, null)
                  name = try(subnet.name, "")
                }]
              }]
            }
          ]
        ]
      ]
    ]
  ])
}

resource "mso_schema_site_vrf_region" "schema_site_vrf_region" {
  for_each           = { for region in local.vrfs_sites_regions : region.key => region }
  schema_id          = each.value.schema_id
  site_id            = each.value.site_id
  template_name      = each.value.template_name
  vrf_name           = each.value.vrf_name
  region_name        = each.value.region_name
  vpn_gateway        = each.value.vpn_gateway
  hub_network_enable = each.value.hub_network_enable
  hub_network        = each.value.hub_network

  dynamic "cidr" {
    for_each = { for cidr in try(each.value.cidr, []) : cidr.cidr_ip => cidr }
    content {
      cidr_ip = cidr.value.cidr_ip
      primary = cidr.value.primary

      dynamic "subnet" {
        for_each = { for subnet in try(each.value.subnet, []) : subnet.ip => subnet }
        content {
          ip   = subnet.value.ip
          zone = subnet.value.zone
          name = subnet.value.name
        }
      }
    }
  }

  depends_on = [mso_schema_site_vrf.schema_site_vrf]
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
          vrf_schema_id          = try(bd.vrf.schema, null) != null ? try(mso_schema.schema[bd.vrf.schema].id, data.mso_schema.template_schema[bd.vrf.schema].id) : null
          vrf_template_name      = try(bd.vrf.template, null)
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
            site_id       = var.manage_sites ? mso_site.site[site.name].id : data.mso_site.template_site[site.name].id
            host_route    = try(site.advertise_host_routes, local.defaults.ndo.schemas.templates.bridge_domains.sites.advertise_host_routes)
            mac           = try(site.mac, local.defaults.ndo.schemas.templates.bridge_domains.sites.mac, "00:22:BD:F8:19:FF")
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
  svi_mac       = each.value.mac

  depends_on = [
    mso_schema_site.schema_site,
    mso_schema_template_bd.schema_template_bd,
  ]
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
              site_id            = var.manage_sites ? mso_site.site[site.name].id : data.mso_site.template_site[site.name].id
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
              site_id       = var.manage_sites ? mso_site.site[site.name].id : data.mso_site.template_site[site.name].id
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
  application_profiles_sites = flatten([
    for schema in local.schemas : [
      for template in try(schema.templates, []) : [
        for ap in try(template.application_profiles, []) : [
          for site in distinct(flatten([for epg in try(ap.endpoint_groups, []) : [for site in try(epg.sites, []) : site.name]])) : {
            key           = "${schema.name}/${template.name}/${ap.name}/${site}"
            schema_id     = mso_schema.schema[schema.name].id
            template_name = template.name
            site_id       = var.manage_sites ? mso_site.site[site].id : data.mso_site.template_site[site].id
            anp_name      = "${ap.name}${local.defaults.ndo.schemas.templates.application_profiles.name_suffix}"
          }
        ]
      ]
    ]
  ])
}

resource "mso_schema_site_anp" "schema_site_anp" {
  for_each      = { for ap in local.application_profiles_sites : ap.key => ap }
  schema_id     = each.value.schema_id
  template_name = each.value.template_name
  site_id       = each.value.site_id
  anp_name      = each.value.anp_name

  depends_on = [
    mso_schema_site.schema_site,
    mso_schema_template_anp.schema_template_anp,
  ]
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
            bd_schema_id               = try(epg.bridge_domain.schema, null) != null ? try(mso_schema.schema[epg.bridge_domain.schema].id, data.mso_schema.template_schema[epg.bridge_domain.schema].id) : null
            bd_template_name           = try(epg.bridge_domain.template, null)
            vrf_name                   = try(epg.vrf.name, null) != null ? "${epg.vrf.name}${local.defaults.ndo.schemas.templates.vrfs.name_suffix}" : null
            vrf_schema_id              = try(epg.vrf.schema, null) != null ? try(mso_schema.schema[epg.vrf.schema].id, data.mso_schema.template_schema[epg.vrf.schema].id) : null
            vrf_template_name          = try(epg.vrf.template, null)
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
  endpoint_groups_sites = flatten([
    for schema in local.schemas : [
      for template in try(schema.templates, []) : [
        for ap in try(template.application_profiles, []) : [
          for epg in try(ap.endpoint_groups, []) : [
            for site in try(epg.sites, []) : {
              key           = "${schema.name}/${template.name}/${ap.name}/${epg.name}/${site.name}"
              schema_id     = mso_schema.schema[schema.name].id
              template_name = template.name
              site_id       = var.manage_sites ? mso_site.site[site.name].id : data.mso_site.template_site[site.name].id
              anp_name      = "${ap.name}${local.defaults.ndo.schemas.templates.application_profiles.name_suffix}"
              epg_name      = "${epg.name}${local.defaults.ndo.schemas.templates.application_profiles.endpoint_groups.name_suffix}"
            }
          ]
        ]
      ]
    ]
  ])
}

resource "mso_schema_site_anp_epg" "schema_site_anp_epg" {
  for_each      = { for epg in local.endpoint_groups_sites : epg.key => epg }
  schema_id     = each.value.schema_id
  template_name = each.value.template_name
  site_id       = each.value.site_id
  anp_name      = each.value.anp_name
  epg_name      = each.value.epg_name

  depends_on = [
    mso_schema_site_anp.schema_site_anp,
    mso_schema_template_anp_epg.schema_template_anp_epg,
  ]
}

locals {
  endpoint_groups_contracts = flatten([
    for schema in local.schemas : [
      for template in try(schema.templates, []) : [
        for ap in try(template.application_profiles, []) : [
          for epg in try(ap.endpoint_groups, []) : concat([
            for contract in try(epg.contracts.consumers, []) : {
              key                    = "${schema.name}/${template.name}/${ap.name}/${epg.name}/${contract.name}/consumer"
              schema_id              = mso_schema.schema[schema.name].id
              template_name          = template.name
              anp_name               = "${ap.name}${local.defaults.ndo.schemas.templates.application_profiles.name_suffix}"
              epg_name               = "${epg.name}${local.defaults.ndo.schemas.templates.application_profiles.endpoint_groups.name_suffix}"
              contract_name          = "${contract.name}${local.defaults.ndo.schemas.templates.contracts.name_suffix}"
              contract_schema_id     = try(contract.schema, null) != null ? try(mso_schema.schema[contract.schema].id, data.mso_schema.template_schema[contract.schema].id) : null
              contract_template_name = try(contract.template, null)
              relationship_type      = "consumer"
            }
            ],
            [
              for contract in try(epg.contracts.providers, []) : {
                key                    = "${schema.name}/${template.name}/${ap.name}/${epg.name}/${contract.name}/provider"
                schema_id              = mso_schema.schema[schema.name].id
                template_name          = template.name
                anp_name               = "${ap.name}${local.defaults.ndo.schemas.templates.application_profiles.name_suffix}"
                epg_name               = "${epg.name}${local.defaults.ndo.schemas.templates.application_profiles.endpoint_groups.name_suffix}"
                contract_name          = "${contract.name}${local.defaults.ndo.schemas.templates.contracts.name_suffix}"
                contract_schema_id     = try(contract.schema, null) != null ? try(mso_schema.schema[contract.schema].id, data.mso_schema.template_schema[contract.schema].id) : null
                contract_template_name = try(contract.template, null)
                relationship_type      = "provider"
              }
          ])
        ]
      ]
    ]
  ])
}

resource "mso_schema_template_anp_epg_contract" "schema_template_anp_epg_contract" {
  for_each               = { for contract in local.endpoint_groups_contracts : contract.key => contract }
  schema_id              = each.value.schema_id
  template_name          = each.value.template_name
  anp_name               = each.value.anp_name
  epg_name               = each.value.epg_name
  contract_name          = each.value.contract_name
  contract_schema_id     = each.value.contract_schema_id
  contract_template_name = each.value.contract_template_name
  relationship_type      = each.value.relationship_type

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
                key                = "${schema.name}/${template.name}/${ap.name}/${epg.name}/${site.name}/${subnet.ip}"
                schema_id          = mso_schema.schema[schema.name].id
                site_id            = var.manage_sites ? mso_site.site[site.name].id : data.mso_site.template_site[site.name].id
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
    mso_schema_site_anp_epg.schema_site_anp_epg,
    mso_schema_template_anp_epg_subnet.schema_template_anp_epg_subnet,
  ]
}

locals {
  endpoint_groups_sites_static_ports = flatten([
    for schema in local.schemas : [
      for template in try(schema.templates, []) : [
        for ap in try(template.application_profiles, []) : [
          for epg in try(ap.endpoint_groups, []) : [
            for site in try(epg.sites, []) : [
              for sp in try(site.static_ports, []) : {
                key                  = "${schema.name}/${template.name}/${ap.name}/${epg.name}/${site.name}/${try(sp.pod, "1")}/${try(sp.node, "")}/${try(sp.node_1, "")}/${try(sp.node_1, "")}/${try(sp.fex, "")}/${try(sp.module, "1")}/${try(sp.port, "")}/${try(sp.channel, "")}/${try(sp.vlan, "")}"
                schema_id            = mso_schema.schema[schema.name].id
                site_id              = var.manage_sites ? mso_site.site[site.name].id : data.mso_site.template_site[site.name].id
                template_name        = template.name
                anp_name             = "${ap.name}${local.defaults.ndo.schemas.templates.application_profiles.name_suffix}"
                epg_name             = "${epg.name}${local.defaults.ndo.schemas.templates.application_profiles.endpoint_groups.name_suffix}"
                path_type            = try(sp.type, local.defaults.ndo.schemas.templates.application_profiles.endpoint_groups.sites.static_ports.type) == "pc" ? "dpc" : try(sp.type, local.defaults.ndo.schemas.templates.application_profiles.endpoint_groups.sites.static_ports.type)
                pod                  = "pod-${try(sp.pod, 1)}"
                leaf                 = try(sp.type, local.defaults.ndo.schemas.templates.application_profiles.endpoint_groups.sites.static_ports.type) == "vpc" ? "${sp.node_1}-${sp.node_2}" : try(sp.node, null)
                path                 = try(sp.type, local.defaults.ndo.schemas.templates.application_profiles.endpoint_groups.sites.static_ports.type) == "port" ? "eth${try(sp.module, 1)}/${sp.port}" : "${sp.channel}${local.defaults.ndo.schemas.templates.application_profiles.endpoint_groups.sites.static_ports.leaf_interface_policy_group_suffix}"
                mode                 = try(sp.mode, local.defaults.ndo.schemas.templates.application_profiles.endpoint_groups.sites.static_ports.mode)
                deployment_immediacy = try(sp.deployment_immediacy, local.defaults.ndo.schemas.templates.application_profiles.endpoint_groups.sites.static_ports.deployment_immediacy)
                vlan                 = try(sp.vlan, null)
                micro_seg_vlan       = try(sp.useg_vlan, null)
                fex                  = try(sp.fex, null)
              }
            ]
          ]
        ]
      ]
    ]
  ])
}

resource "mso_schema_site_anp_epg_static_port" "schema_site_anp_epg_static_port" {
  for_each             = { for sp in local.endpoint_groups_sites_static_ports : sp.key => sp }
  schema_id            = each.value.schema_id
  site_id              = each.value.site_id
  template_name        = each.value.template_name
  anp_name             = each.value.anp_name
  epg_name             = each.value.epg_name
  path_type            = each.value.path_type
  pod                  = each.value.pod
  leaf                 = each.value.leaf
  path                 = each.value.path
  mode                 = each.value.mode
  deployment_immediacy = each.value.deployment_immediacy
  vlan                 = each.value.vlan
  micro_seg_vlan       = each.value.micro_seg_vlan
  fex                  = each.value.fex

  depends_on = [
    mso_schema_site_anp_epg.schema_site_anp_epg,
  ]
}

locals {
  endpoint_groups_sites_static_leafs = flatten([
    for schema in local.schemas : [
      for template in try(schema.templates, []) : [
        for ap in try(template.application_profiles, []) : [
          for epg in try(ap.endpoint_groups, []) : [
            for site in try(epg.sites, []) : [
              for sl in try(site.static_leafs, []) : {
                key             = "${schema.name}/${template.name}/${ap.name}/${epg.name}/${site.name}/${try(sl.pod, "1")}/${try(sl.node, "")}/${try(sl.vlan, "")}"
                schema_id       = mso_schema.schema[schema.name].id
                site_id         = var.manage_sites ? mso_site.site[site.name].id : data.mso_site.template_site[site.name].id
                template_name   = template.name
                anp_name        = "${ap.name}${local.defaults.ndo.schemas.templates.application_profiles.name_suffix}"
                epg_name        = "${epg.name}${local.defaults.ndo.schemas.templates.application_profiles.endpoint_groups.name_suffix}"
                path            = "topology/pod-${try(sl.pod, "1")}/node-${sl.node}"
                port_encap_vlan = sl.vlan
              }
            ]
          ]
        ]
      ]
    ]
  ])
}

resource "mso_schema_site_anp_epg_static_leaf" "schema_site_anp_epg_static_leaf" {
  for_each        = { for sl in local.endpoint_groups_sites_static_leafs : sl.key => sl }
  schema_id       = each.value.schema_id
  site_id         = each.value.site_id
  template_name   = each.value.template_name
  anp_name        = each.value.anp_name
  epg_name        = each.value.epg_name
  path            = each.value.path
  port_encap_vlan = each.value.port_encap_vlan

  depends_on = [
    mso_schema_site_anp_epg.schema_site_anp_epg,
  ]
}

locals {
  endpoint_groups_sites_domains_physical = flatten([
    for schema in local.schemas : [
      for template in try(schema.templates, []) : [
        for ap in try(template.application_profiles, []) : [
          for epg in try(ap.endpoint_groups, []) : [
            for site in try(epg.sites, []) : [
              for pd in try(site.physical_domains, []) : {
                key                  = "${schema.name}/${template.name}/${ap.name}/${epg.name}/${site.name}/${pd.name}"
                schema_id            = mso_schema.schema[schema.name].id
                site_id              = var.manage_sites ? mso_site.site[site.name].id : data.mso_site.template_site[site.name].id
                template_name        = template.name
                anp_name             = "${ap.name}${local.defaults.ndo.schemas.templates.application_profiles.name_suffix}"
                epg_name             = "${epg.name}${local.defaults.ndo.schemas.templates.application_profiles.endpoint_groups.name_suffix}"
                domain_name          = "${pd.name}${local.defaults.ndo.schemas.templates.application_profiles.endpoint_groups.physical_domain_name_suffix}"
                domain_type          = "physicalDomain"
                deploy_immediacy     = try(pd.deployment_immediacy, local.defaults.ndo.schemas.templates.application_profiles.endpoint_groups.sites.physical_domains.deployment_immediacy)
                resolution_immediacy = try(pd.resolution_immediacy, local.defaults.ndo.schemas.templates.application_profiles.endpoint_groups.sites.physical_domains.resolution_immediacy)
              }
            ]
          ]
        ]
      ]
    ]
  ])
}

resource "mso_schema_site_anp_epg_domain" "schema_site_anp_epg_domain_physical" {
  for_each             = { for pd in local.endpoint_groups_sites_domains_physical : pd.key => pd }
  schema_id            = each.value.schema_id
  site_id              = each.value.site_id
  template_name        = each.value.template_name
  anp_name             = each.value.anp_name
  epg_name             = each.value.epg_name
  domain_name          = each.value.domain_name
  domain_type          = each.value.domain_type
  deploy_immediacy     = each.value.deploy_immediacy
  resolution_immediacy = each.value.resolution_immediacy

  depends_on = [
    mso_schema_site_anp_epg.schema_site_anp_epg,
  ]
}

locals {
  endpoint_groups_sites_domains_vmware = flatten([
    for schema in local.schemas : [
      for template in try(schema.templates, []) : [
        for ap in try(template.application_profiles, []) : [
          for epg in try(ap.endpoint_groups, []) : [
            for site in try(epg.sites, []) : [
              for vmm in try(site.vmware_vmm_domains, []) : {
                key                      = "${schema.name}/${template.name}/${ap.name}/${epg.name}/${site.name}/${vmm.name}"
                schema_id                = mso_schema.schema[schema.name].id
                site_id                  = var.manage_sites ? mso_site.site[site.name].id : data.mso_site.template_site[site.name].id
                template_name            = template.name
                anp_name                 = "${ap.name}${local.defaults.ndo.schemas.templates.application_profiles.name_suffix}"
                epg_name                 = "${epg.name}${local.defaults.ndo.schemas.templates.application_profiles.endpoint_groups.name_suffix}"
                domain_name              = "${vmm.name}${local.defaults.ndo.schemas.templates.application_profiles.endpoint_groups.vmm_domain_name_suffix}"
                domain_type              = "vmmDomain"
                vmm_domain_type          = "VMware"
                deploy_immediacy         = try(vmm.deployment_immediacy, local.defaults.ndo.schemas.templates.application_profiles.endpoint_groups.sites.physical_domains.deployment_immediacy)
                resolution_immediacy     = try(vmm.resolution_immediacy, local.defaults.ndo.schemas.templates.application_profiles.endpoint_groups.sites.physical_domains.resolution_immediacy)
                vlan_encap_mode          = try(vmm.vlan_mode, local.defaults.ndo.schemas.templates.application_profiles.endpoint_groups.sites.vmware_vmm_domains.vlan_mode)
                allow_micro_segmentation = try(vmm.u_segmentation, local.defaults.ndo.schemas.templates.application_profiles.endpoint_groups.sites.vmware_vmm_domains.u_segmentation)
                switching_mode           = "native"
                switch_type              = "default"
                micro_seg_vlan_type      = try(vmm.u_segmentation, local.defaults.ndo.schemas.templates.application_profiles.endpoint_groups.sites.vmware_vmm_domains.u_segmentation) && try(vmm.vlan_mode, local.defaults.ndo.schemas.templates.application_profiles.endpoint_groups.sites.vmware_vmm_domains.vlan_mode) == "static" ? "vlan" : null
                micro_seg_vlan           = try(vmm.u_segmentation, local.defaults.ndo.schemas.templates.application_profiles.endpoint_groups.sites.vmware_vmm_domains.u_segmentation) && try(vmm.vlan_mode, local.defaults.ndo.schemas.templates.application_profiles.endpoint_groups.sites.vmware_vmm_domains.vlan_mode) == "static" ? vmm.useg_vlan : null
                port_encap_vlan_type     = try(vmm.vlan_mode, local.defaults.ndo.schemas.templates.application_profiles.endpoint_groups.sites.vmware_vmm_domains.vlan_mode) == "static" ? "vlan" : null
                port_encap_vlan          = try(vmm.vlan_mode, local.defaults.ndo.schemas.templates.application_profiles.endpoint_groups.sites.vmware_vmm_domains.vlan_mode) == "static" ? vmm.vlan : null
              }
            ]
          ]
        ]
      ]
    ]
  ])
}

resource "mso_schema_site_anp_epg_domain" "schema_site_anp_epg_domain_vmware" {
  for_each                 = { for vmm in local.endpoint_groups_sites_domains_vmware : vmm.key => vmm }
  schema_id                = each.value.schema_id
  site_id                  = each.value.site_id
  template_name            = each.value.template_name
  anp_name                 = each.value.anp_name
  epg_name                 = each.value.epg_name
  domain_name              = each.value.domain_name
  domain_type              = each.value.domain_type
  vmm_domain_type          = each.value.vmm_domain_type
  deploy_immediacy         = each.value.deploy_immediacy
  resolution_immediacy     = each.value.resolution_immediacy
  vlan_encap_mode          = each.value.vlan_encap_mode
  allow_micro_segmentation = each.value.allow_micro_segmentation
  switching_mode           = each.value.switching_mode
  switch_type              = each.value.switch_type
  micro_seg_vlan_type      = each.value.micro_seg_vlan_type
  micro_seg_vlan           = each.value.micro_seg_vlan
  port_encap_vlan_type     = each.value.port_encap_vlan_type
  port_encap_vlan          = each.value.port_encap_vlan

  depends_on = [
    mso_schema_site_anp_epg.schema_site_anp_epg,
  ]
}

locals {
  endpoint_groups_sites_selectors = flatten([
    for schema in local.schemas : [
      for template in try(schema.templates, []) : [
        for ap in try(template.application_profiles, []) : [
          for epg in try(ap.endpoint_groups, []) : [
            for site in try(epg.sites, []) : [
              for selector in try(site.selectors, []) : {
                key           = "${schema.name}/${template.name}/${ap.name}/${epg.name}/${site.name}/${selector.name}"
                schema_id     = mso_schema.schema[schema.name].id
                site_id       = var.manage_sites ? mso_site.site[site.name].id : data.mso_site.template_site[site.name].id
                template_name = template.name
                anp_name      = "${ap.name}${local.defaults.ndo.schemas.templates.application_profiles.name_suffix}"
                epg_name      = "${epg.name}${local.defaults.ndo.schemas.templates.application_profiles.endpoint_groups.name_suffix}"
                name          = selector.name
                expressions = [for expression in try(selector.expressions, []) : {
                  key_     = "${expression.key}/${expression.operator}/${expression.value}"
                  key      = expression.key
                  operator = expression.operator
                  value    = expression.value
                }]
              }
            ]
          ]
        ]
      ]
    ]
  ])
}

resource "mso_schema_site_anp_epg_selector" "schema_site_anp_epg_selector" {
  for_each      = { for selector in local.endpoint_groups_sites_selectors : selector.key => selector }
  schema_id     = each.value.schema_id
  site_id       = each.value.site_id
  template_name = each.value.template_name
  anp_name      = each.value.anp_name
  epg_name      = each.value.epg_name
  name          = each.value.name

  dynamic "expressions" {
    for_each = { for expression in try(each.value.expressions, []) : expression.key_ => expression }
    content {
      key      = expressions.value.key
      operator = expressions.value.operator
      value    = expressions.value.value
    }
  }

  depends_on = [
    mso_schema_site_anp_epg.schema_site_anp_epg,
  ]
}

locals {
  l3outs = flatten([
    for schema in local.schemas : [
      for template in try(schema.templates, []) : [
        for l3out in try(template.l3outs, []) : {
          key               = "${schema.name}/${template.name}/${l3out.name}"
          schema_id         = mso_schema.schema[schema.name].id
          template_name     = template.name
          l3out_name        = "${l3out.name}${local.defaults.ndo.schemas.templates.l3outs.name_suffix}"
          display_name      = "${l3out.name}${local.defaults.ndo.schemas.templates.l3outs.name_suffix}"
          vrf_name          = "${l3out.vrf.name}${local.defaults.ndo.schemas.templates.vrfs.name_suffix}"
          vrf_schema_id     = try(l3out.vrf.schema, null) != null ? try(mso_schema.schema[l3out.vrf.schema].id, data.mso_schema.template_schema[l3out.vrf.schema].id) : null
          vrf_template_name = try(l3out.vrf.template, null)
        }
      ]
    ]
  ])
}

resource "mso_schema_template_l3out" "schema_template_l3out" {
  for_each          = { for l3out in local.l3outs : l3out.key => l3out }
  schema_id         = each.value.schema_id
  template_name     = each.value.template_name
  l3out_name        = each.value.l3out_name
  display_name      = each.value.display_name
  vrf_name          = each.value.vrf_name
  vrf_schema_id     = each.value.vrf_schema_id
  vrf_template_name = each.value.vrf_template_name

  depends_on = [mso_schema_template_vrf.schema_template_vrf]
}

locals {
  external_epgs = flatten([
    for schema in local.schemas : [
      for template in try(schema.templates, []) : [
        for epg in try(template.external_endpoint_groups, []) : {
          key                        = "${schema.name}/${template.name}/${epg.name}"
          schema_id                  = mso_schema.schema[schema.name].id
          template_name              = template.name
          external_epg_name          = "${epg.name}${local.defaults.ndo.schemas.templates.external_endpoint_groups.name_suffix}"
          display_name               = "${epg.name}${local.defaults.ndo.schemas.templates.external_endpoint_groups.name_suffix}"
          external_epg_type          = try(epg.type, local.defaults.ndo.schemas.templates.external_endpoint_groups.type)
          vrf_name                   = "${epg.vrf.name}${local.defaults.ndo.schemas.templates.vrfs.name_suffix}"
          vrf_schema_id              = try(epg.vrf.schema, null) != null ? try(mso_schema.schema[epg.vrf.schema].id, data.mso_schema.template_schema[epg.vrf.schema].id) : null
          vrf_template_name          = try(epg.vrf.template, null)
          include_in_preferred_group = try(epg.preferred_group, local.defaults.ndo.schemas.templates.external_endpoint_groups.preferred_group)
          l3out_name                 = try(epg.l3out.name, null) != null ? "${epg.l3out.name}${local.defaults.ndo.schemas.templates.l3outs.name_suffix}" : null
          l3out_schema_id            = try(epg.l3out.schema, null) != null ? try(mso_schema.schema[epg.l3out.schema].id, data.mso_schema.template_schema[epg.l3out.schema].id) : null
          l3out_template_name        = try(epg.l3out.template, null)
          anp_name                   = try(epg.application_profile.name, null) != null ? "${epg.application_profile.name}${local.defaults.ndo.schemas.templates.application_profiles.name_suffix}" : null
          anp_schema_id              = try(epg.application_profile.schema, null) != null ? try(mso_schema.schema[epg.application_profile.schema].id, data.mso_schema.template_schema[epg.application_profile.schema].id) : null
          anp_template_name          = try(epg.application_profile.template, null)
        }
      ]
    ]
  ])
}

resource "mso_schema_template_external_epg" "schema_template_external_epg" {
  for_each                   = { for epg in local.external_epgs : epg.key => epg }
  schema_id                  = each.value.schema_id
  template_name              = each.value.template_name
  external_epg_name          = each.value.external_epg_name
  display_name               = each.value.display_name
  external_epg_type          = each.value.external_epg_type
  vrf_name                   = each.value.vrf_name
  vrf_schema_id              = each.value.vrf_schema_id
  vrf_template_name          = each.value.vrf_template_name
  include_in_preferred_group = each.value.include_in_preferred_group
  l3out_name                 = each.value.l3out_name
  l3out_schema_id            = each.value.l3out_schema_id
  l3out_template_name        = each.value.l3out_template_name
  anp_name                   = each.value.anp_name
  anp_schema_id              = each.value.anp_schema_id
  anp_template_name          = each.value.anp_template_name

  depends_on = [
    mso_schema_template_vrf.schema_template_vrf,
    mso_schema_template_l3out.schema_template_l3out,
    mso_schema_template_anp.schema_template_anp,
  ]
}

locals {
  external_epgs_contracts = flatten([
    for schema in local.schemas : [
      for template in try(schema.templates, []) : [
        for epg in try(template.external_endpoint_groups, []) : concat([
          for contract in try(epg.contracts.consumers, []) : {
            key                    = "${schema.name}/${template.name}/${epg.name}/${contract.name}/consumer"
            schema_id              = mso_schema.schema[schema.name].id
            template_name          = template.name
            external_epg_name      = "${epg.name}${local.defaults.ndo.schemas.templates.external_endpoint_groups.name_suffix}"
            contract_name          = "${contract.name}${local.defaults.ndo.schemas.templates.contracts.name_suffix}"
            contract_schema_id     = try(contract.schema, null) != null ? try(mso_schema.schema[contract.schema].id, data.mso_schema.template_schema[contract.schema].id) : null
            contract_template_name = try(contract.template, null)
            relationship_type      = "consumer"
          }
          ],
          [
            for contract in try(epg.contracts.providers, []) : {
              key                    = "${schema.name}/${template.name}/${epg.name}/${contract.name}/provider"
              schema_id              = mso_schema.schema[schema.name].id
              template_name          = template.name
              external_epg_name      = "${epg.name}${local.defaults.ndo.schemas.templates.external_endpoint_groups.name_suffix}"
              contract_name          = "${contract.name}${local.defaults.ndo.schemas.templates.contracts.name_suffix}"
              contract_schema_id     = try(contract.schema, null) != null ? try(mso_schema.schema[contract.schema].id, data.mso_schema.template_schema[contract.schema].id) : null
              contract_template_name = try(contract.template, null)
              relationship_type      = "provider"
            }
        ])
      ]
    ]
  ])
}

resource "mso_schema_template_external_epg_contract" "schema_template_external_epg_contract" {
  for_each               = { for contract in local.external_epgs_contracts : contract.key => contract }
  schema_id              = each.value.schema_id
  template_name          = each.value.template_name
  external_epg_name      = each.value.external_epg_name
  contract_name          = each.value.contract_name
  contract_schema_id     = each.value.contract_schema_id
  contract_template_name = each.value.contract_template_name
  relationship_type      = each.value.relationship_type

  depends_on = [
    mso_schema_template_external_epg.schema_template_external_epg,
    mso_schema_template_contract.schema_template_contract,
  ]
}

locals {
  external_epgs_subnets = flatten([
    for schema in local.schemas : [
      for template in try(schema.templates, []) : [
        for epg in try(template.external_endpoint_groups, []) : [
          for subnet in try(epg.subnets, []) : {
            key               = "${schema.name}/${template.name}/${epg.name}/${subnet.prefix}"
            schema_id         = mso_schema.schema[schema.name].id
            template_name     = template.name
            external_epg_name = "${epg.name}${local.defaults.ndo.schemas.templates.external_endpoint_groups.name_suffix}"
            ip                = subnet.prefix
            scope = concat(
              try(subnet.shared_security, local.defaults.ndo.schemas.templates.external_endpoint_groups.subnets.shared_security) ? ["shared-security"] : [],
              try(subnet.export_route_control, local.defaults.ndo.schemas.templates.external_endpoint_groups.subnets.export_route_control) ? ["export-rtctrl"] : [],
              try(subnet.import_route_control, local.defaults.ndo.schemas.templates.external_endpoint_groups.subnets.import_route_control) ? ["import-rtctrl"] : [],
              try(subnet.shared_route_control, local.defaults.ndo.schemas.templates.external_endpoint_groups.subnets.shared_route_control) ? ["shared-rtctrl"] : [],
              try(subnet.import_security, local.defaults.ndo.schemas.templates.external_endpoint_groups.subnets.import_security) ? ["import-security"] : []
            )
            aggregate = concat(
              try(subnet.aggregate_export, local.defaults.ndo.schemas.templates.external_endpoint_groups.subnets.aggregate_export) ? ["export-rtctrl"] : [],
              try(subnet.aggregate_import, local.defaults.ndo.schemas.templates.external_endpoint_groups.subnets.aggregate_import) ? ["import-rtctrl"] : [],
              try(subnet.aggregate_shared, local.defaults.ndo.schemas.templates.external_endpoint_groups.subnets.aggregate_shared) ? ["shared-rtctrl"] : []
            )
          }
        ]
      ]
    ]
  ])
}

resource "mso_schema_template_external_epg_subnet" "schema_template_external_epg_subnet" {
  for_each          = { for subnet in local.external_epgs_subnets : subnet.key => subnet }
  schema_id         = each.value.schema_id
  template_name     = each.value.template_name
  external_epg_name = each.value.external_epg_name
  ip                = each.value.ip
  scope             = each.value.scope
  aggregate         = each.value.aggregate

  depends_on = [
    mso_schema_template_external_epg.schema_template_external_epg,
  ]
}

locals {
  external_epgs_selectors = flatten([
    for schema in local.schemas : [
      for template in try(schema.templates, []) : [
        for epg in try(template.external_endpoint_groups, []) : [
          for selector in try(epg.selectors, []) : {
            key               = "${schema.name}/${template.name}/${epg.name}/${selector.name}"
            schema_id         = mso_schema.schema[schema.name].id
            template_name     = template.name
            external_epg_name = "${epg.name}${local.defaults.ndo.schemas.templates.external_endpoint_groups.name_suffix}"
            name              = selector.name
            expressions = [for ip in try(selector.ips, []) : {
              key_     = ip
              key      = "ipAddress"
              operator = "equals"
              value    = ip
            }]
          }
        ]
      ]
    ]
  ])
}

resource "mso_schema_template_external_epg_selector" "schema_template_external_epg_selector" {
  for_each          = { for selector in local.external_epgs_selectors : selector.key => selector }
  schema_id         = each.value.schema_id
  template_name     = each.value.template_name
  external_epg_name = each.value.external_epg_name
  name              = each.value.name

  dynamic "expressions" {
    for_each = { for expression in try(each.value.expressions, []) : expression.key_ => expression }
    content {
      key      = expressions.value.key
      operator = expressions.value.operator
      value    = expressions.value.value
    }
  }

  depends_on = [
    mso_schema_template_external_epg.schema_template_external_epg,
  ]
}

locals {
  external_epgs_sites_selectors = flatten([
    for schema in local.schemas : [
      for template in try(schema.templates, []) : [
        for epg in try(template.external_endpoint_groups, []) : [
          for site in try(epg.sites, []) : [
            for selector in try(site.selectors, []) : [
              for ip in try(selector.ips, []) : {
                key               = "${schema.name}/${template.name}/${epg.name}/${site.name}/${selector.name}/${ip}"
                schema_id         = mso_schema.schema[schema.name].id
                template_name     = template.name
                site_id           = var.manage_sites ? mso_site.site[site.name].id : data.mso_site.template_site[site.name].id
                external_epg_name = "${epg.name}${local.defaults.ndo.schemas.templates.external_endpoint_groups.name_suffix}"
                name              = selector.name
                ip                = ip
              }
            ]
          ]
        ]
      ]
    ]
  ])
}

resource "mso_schema_site_external_epg_selector" "schema_site_external_epg_selector" {
  for_each          = { for selector in local.external_epgs_sites_selectors : selector.key => selector }
  schema_id         = each.value.schema_id
  template_name     = each.value.template_name
  site_id           = each.value.site_id
  external_epg_name = each.value.external_epg_name
  name              = each.value.name
  ip                = each.value.ip

  depends_on = [
    mso_schema_template_external_epg_selector.schema_template_external_epg_selector,
  ]
}

locals {
  service_graphs = flatten([
    for schema in local.schemas : [
      for template in try(schema.templates, []) : [
        for sg in try(template.service_graphs, []) : {
          key                = "${schema.name}/${template.name}/${sg.name}"
          schema_id          = mso_schema.schema[schema.name].id
          template_name      = template.name
          service_graph_name = "${sg.name}${local.defaults.ndo.schemas.templates.service_graphs.name_suffix}"
          service_node_type  = "other"
          description        = try(sg.description, null)
          site_nodes = flatten([
            for node in try(sg.nodes, []) : [
              for site in try(node.sites, []) : {
                key         = "${var.manage_sites ? mso_site.site[site.name].id : data.mso_site.template_site[site.name].id}/${try(site.tenant, template.tenant)}/${site.device}"
                site_id     = var.manage_sites ? mso_site.site[site.name].id : data.mso_site.template_site[site.name].id
                tenant_name = try(site.tenant, template.tenant)
                node_name   = "${site.device}${local.defaults.ndo.schemas.templates.service_graphs.device_name_suffix}"
              }
            ]
          ])
        }
      ]
    ]
  ])
}

resource "mso_schema_template_service_graph" "schema_template_service_graph" {
  for_each           = { for sg in local.service_graphs : sg.key => sg }
  schema_id          = each.value.schema_id
  template_name      = each.value.template_name
  service_graph_name = each.value.service_graph_name
  service_node_type  = each.value.service_node_type
  description        = each.value.description

  dynamic "site_nodes" {
    for_each = { for site_node in try(each.value.site_nodes, []) : site_node.key => site_node }
    content {
      site_id     = site_nodes.value.site_id
      tenant_name = site_nodes.value.tenant_name
      node_name   = site_nodes.value.node_name
    }
  }
}
