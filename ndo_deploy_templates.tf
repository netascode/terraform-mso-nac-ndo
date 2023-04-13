locals {
  deploy_templates = flatten([
    for schema in try(local.ndo.schemas, {}) : [
      for template in try(schema.templates, {}) : {
        key           = "${schema.name}/${template.name}"
        schema_name   = schema.name
        template_name = template.name
      }
    ]
  ])
}

# Deploy templates NDO < v3.7
/* resource "mso_schema_template_deploy" "template" {
  for_each      = { for template in local.deploy_templates : template.key => template if var.deploy_templates }
  schema_id     = mso_schema.schema[each.value.schema_name].id
  template_name = each.value.template_name
} */

# Deploy templates NDO v3.7+
resource "mso_schema_template_deploy_ndo" "template" {
  for_each      = { for template in local.deploy_templates : template.key => template if var.deploy_templates }
  schema_id     = mso_schema.schema[each.value.schema_name].id
  template_name = each.value.template_name

  depends_on = [
    mso_schema.schema,
    mso_schema_site.schema_site,
    mso_schema_template_vrf.schema_template_vrf,
    mso_schema_template_bd.schema_template_bd,
    mso_schema_site_bd.schema_site_bd,
    mso_schema_template_bd_subnet.schema_template_bd_subnet,
    mso_schema_site_bd_subnet.schema_site_bd_subnet,
    mso_schema_template_anp.schema_template_anp,
    mso_schema_site_anp.schema_site_anp,
    mso_schema_template_anp_epg.schema_template_anp_epg,
    mso_schema_site_anp_epg.schema_site_anp_epg,
  ]
}
