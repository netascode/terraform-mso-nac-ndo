locals {
  unmanaged_schemas = [for schema in try(local.ndo.schemas, []) : schema if !var.manage_schemas && var.deploy_templates]
  deploy_templates = flatten([
    for schema in concat(local.schemas, local.unmanaged_schemas) : [
      for template in try(schema.templates, {}) : {
        key           = "${schema.name}/${template.name}"
        schema_name   = schema.name
        template_name = template.name
        deploy_order  = try(template.deploy_order, 1)
      }
    ]
  ])
}

data "mso_schema" "schema" {
  for_each = { for schema in local.unmanaged_schemas : schema.name => schema }
  name     = each.value.name
}

resource "mso_schema_template_deploy_ndo" "template" {
  for_each      = { for template in local.deploy_templates : template.key => template if var.deploy_templates && template.deploy_order == 1 }
  schema_id     = var.manage_schemas ? mso_schema.schema[each.value.schema_name].id : data.mso_schema.schema[each.value.schema_name].id
  template_name = each.value.template_name

  depends_on = [
    mso_schema.schema,
    mso_schema_site.schema_site,
    mso_schema_template_filter_entry.schema_template_filter_entry,
    mso_schema_template_contract.schema_template_contract,
    mso_rest.schema_site_contract,
    mso_schema_template_contract_service_graph.schema_template_contract_service_graph,
    mso_schema_site_contract_service_graph.schema_site_contract_service_graph,
    mso_schema_template_vrf.schema_template_vrf,
    mso_schema_site_vrf.schema_site_vrf,
    mso_schema_template_vrf_contract.schema_template_vrf_contract,
    mso_schema_site_vrf_region.schema_site_vrf_region,
    mso_schema_template_bd.schema_template_bd,
    mso_schema_site_bd.schema_site_bd,
    mso_schema_template_bd_subnet.schema_template_bd_subnet,
    mso_schema_site_bd_subnet.schema_site_bd_subnet,
    mso_schema_site_bd_l3out.schema_site_bd_l3out,
    mso_schema_template_anp.schema_template_anp,
    mso_schema_site_anp.schema_site_anp,
    mso_schema_template_anp_epg.schema_template_anp_epg,
    mso_schema_site_anp_epg.schema_site_anp_epg,
    mso_schema_template_anp_epg_contract.schema_template_anp_epg_contract,
    mso_schema_template_anp_epg_subnet.schema_template_anp_epg_subnet,
    mso_schema_site_anp_epg_subnet.schema_site_anp_epg_subnet,
    mso_schema_site_anp_epg_bulk_staticport.schema_site_anp_epg_bulk_staticport,
    mso_schema_site_anp_epg_static_leaf.schema_site_anp_epg_static_leaf,
    mso_schema_site_anp_epg_domain.schema_site_anp_epg_domain_physical,
    mso_schema_site_anp_epg_domain.schema_site_anp_epg_domain_vmware,
    mso_schema_site_anp_epg_selector.schema_site_anp_epg_selector,
    mso_schema_template_l3out.schema_template_l3out,
    mso_schema_template_external_epg.schema_template_external_epg,
    mso_schema_template_external_epg_contract.schema_template_external_epg_contract,
    mso_schema_template_external_epg_subnet.schema_template_external_epg_subnet,
    mso_schema_template_external_epg_selector.schema_template_external_epg_selector,
    mso_schema_site_external_epg_selector.schema_site_external_epg_selector,
    mso_schema_template_service_graph.schema_template_service_graph,
    mso_schema_site_service_graph.schema_site_service_graph,
    mso_rest.schema_site_service_graph,
  ]
}

resource "mso_schema_template_deploy_ndo" "template2" {
  for_each      = { for template in local.deploy_templates : template.key => template if var.deploy_templates && template.deploy_order == 2 }
  schema_id     = var.manage_schemas ? mso_schema.schema[each.value.schema_name].id : data.mso_schema.schema[each.value.schema_name].id
  template_name = each.value.template_name

  depends_on = [mso_schema_template_deploy_ndo.template]
}

resource "mso_schema_template_deploy_ndo" "template3" {
  for_each      = { for template in local.deploy_templates : template.key => template if var.deploy_templates && template.deploy_order == 3 }
  schema_id     = var.manage_schemas ? mso_schema.schema[each.value.schema_name].id : data.mso_schema.schema[each.value.schema_name].id
  template_name = each.value.template_name

  depends_on = [
    mso_schema_template_deploy_ndo.template,
    mso_schema_template_deploy_ndo.template2,
  ]
}
