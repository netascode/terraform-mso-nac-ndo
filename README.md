<!-- BEGIN_TF_DOCS -->
[![Tests](https://github.com/netascode/terraform-mso-nac-ndo/actions/workflows/test.yml/badge.svg)](https://github.com/netascode/terraform-mso-nac-ndo/actions/workflows/test.yml)

# Terraform NDO Nexus-as-Code Module

A Terraform module to configure Nexus Dashboard Orchestrator (NDO).

This module is part of the Cisco [*Nexus-as-Code*](https://cisco.com/go/nexusascode) project. Its goal is to allow users to instantiate network fabrics in minutes using an easy to use, opinionated data model. It takes away the complexity of having to deal with references, dependencies or loops. By completely separating data (defining variables) from logic (infrastructure declaration), it allows the user to focus on describing the intended configuration while using a set of maintained and tested Terraform Modules without the need to understand the low-level ACI object model. More information can be found here: https://cisco.com/go/nexusascode.

## Usage

This module supports an inventory driven approach, where a complete NDO configuration or parts of it are either modeled in one or more YAML files or natively using Terraform variables.

There are six configuration sections which can be selectively enabled or disabled using module flags:

- `system`: Manage system level configuration like banners
- `sites`: Enable sites in NDO
- `site_connectivity`: Manage Multi-Site connectivity configuration
- `tenants`: Configure tenants using NDO
- `schemas`: Configurations applied at the schema and template level (e.g., VRFs and Bridge Domains)
- `deploy_templates`: Automatically deploy templates

The full data model documentation is available here: https://developer.cisco.com/docs/nexus-as-code/#!data-model

The module currently supports only NDO version 3.7.

## Examples

Configuring a Tenant using YAML:

#### `ndo.yaml`

```hcl
ndo:
  sites:
    - name: APIC1
      id: 1
      apic_urls:
        - "https://10.1.1.1"
  tenants:
    - name: NDO1
      sites:
        - name: APIC1
```

#### `main.tf`

```hcl
module "tenant" {
  source  = "netascode/nac-ndo/mso"
  version = ">= 0.7.0"

  yaml_files = ["ndo.yaml"]

  manage_sites   = true
  manage_tenants = true
}
```

Configuring a Site using native HCL:

#### `main.tf`

```hcl
module "site" {
  source  = "netascode/nac-ndo/mso"
  version = ">= 0.7.0"

  model = {
    ndo = {
      sites = [
        {
          name      = "APIC1"
          id        = 1
          apic_urls = ["https://10.1.1.1"]
        }
      ]
    }
  }

  manage_sites = true
}
```

## Issues

Depending on the exact configuration, there might be issues with the NDO API returning errors due to concurrent operations. In this case one can use the `parallelism=1` command line attribute to ensure all resource operations are executed in sequence.

```shell
$ terraform apply -parallelism=1
```

Alternatively, an environment variable can be used as well.

```shell
$ export TF_CLI_ARGS_apply="-parallelism=1"
```

## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.4.0 |
| <a name="requirement_local"></a> [local](#requirement\_local) | >= 2.3.0 |
| <a name="requirement_mso"></a> [mso](#requirement\_mso) | = 1.1.0 |
| <a name="requirement_utils"></a> [utils](#requirement\_utils) | >= 0.2.5 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_deploy_templates"></a> [deploy\_templates](#input\_deploy\_templates) | Flag to indicate if templates should be deployed. | `bool` | `false` | no |
| <a name="input_manage_schemas"></a> [manage\_schemas](#input\_manage\_schemas) | Flag to indicate if schemas should be managed. | `bool` | `false` | no |
| <a name="input_manage_site_connectivity"></a> [manage\_site\_connectivity](#input\_manage\_site\_connectivity) | Flag to indicate if site connectivity be managed. | `bool` | `false` | no |
| <a name="input_manage_sites"></a> [manage\_sites](#input\_manage\_sites) | Flag to indicate if sites should be managed. | `bool` | `false` | no |
| <a name="input_manage_system"></a> [manage\_system](#input\_manage\_system) | Flag to indicate if system level configuration should be managed. | `bool` | `false` | no |
| <a name="input_manage_tenants"></a> [manage\_tenants](#input\_manage\_tenants) | Flag to indicate if tenants be managed. | `bool` | `false` | no |
| <a name="input_managed_schemas"></a> [managed\_schemas](#input\_managed\_schemas) | List of schema names to be managed. By default all schemas will be managed. | `list(string)` | `[]` | no |
| <a name="input_managed_tenants"></a> [managed\_tenants](#input\_managed\_tenants) | List of tenant names to be managed. By default all tenants will be managed. | `list(string)` | `[]` | no |
| <a name="input_model"></a> [model](#input\_model) | As an alternative to YAML files, a native Terraform data structure can be provided as well. | `map(any)` | `{}` | no |
| <a name="input_write_default_values_file"></a> [write\_default\_values\_file](#input\_write\_default\_values\_file) | Write all default values to a YAML file. Value is a path pointing to the file to be created. | `string` | `""` | no |
| <a name="input_yaml_directories"></a> [yaml\_directories](#input\_yaml\_directories) | List of paths to YAML directories. | `list(string)` | `[]` | no |
| <a name="input_yaml_files"></a> [yaml\_files](#input\_yaml\_files) | List of paths to YAML files. | `list(string)` | `[]` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_default_values"></a> [default\_values](#output\_default\_values) | All default values. |
| <a name="output_model"></a> [model](#output\_model) | Full model. |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_local"></a> [local](#provider\_local) | >= 2.3.0 |
| <a name="provider_mso"></a> [mso](#provider\_mso) | = 1.1.0 |
| <a name="provider_utils"></a> [utils](#provider\_utils) | >= 0.2.5 |

## Resources

| Name | Type |
|------|------|
| [local_sensitive_file.defaults](https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/sensitive_file) | resource |
| [mso_remote_location.remote_location](https://registry.terraform.io/providers/CiscoDevNet/mso/1.1.0/docs/resources/remote_location) | resource |
| [mso_rest.schema_site_contract](https://registry.terraform.io/providers/CiscoDevNet/mso/1.1.0/docs/resources/rest) | resource |
| [mso_rest.schema_site_service_graph](https://registry.terraform.io/providers/CiscoDevNet/mso/1.1.0/docs/resources/rest) | resource |
| [mso_rest.site_connectivity](https://registry.terraform.io/providers/CiscoDevNet/mso/1.1.0/docs/resources/rest) | resource |
| [mso_rest.system_config](https://registry.terraform.io/providers/CiscoDevNet/mso/1.1.0/docs/resources/rest) | resource |
| [mso_schema.schema](https://registry.terraform.io/providers/CiscoDevNet/mso/1.1.0/docs/resources/schema) | resource |
| [mso_schema_site.schema_site](https://registry.terraform.io/providers/CiscoDevNet/mso/1.1.0/docs/resources/schema_site) | resource |
| [mso_schema_site_anp.schema_site_anp](https://registry.terraform.io/providers/CiscoDevNet/mso/1.1.0/docs/resources/schema_site_anp) | resource |
| [mso_schema_site_anp_epg.schema_site_anp_epg](https://registry.terraform.io/providers/CiscoDevNet/mso/1.1.0/docs/resources/schema_site_anp_epg) | resource |
| [mso_schema_site_anp_epg_bulk_staticport.schema_site_anp_epg_bulk_staticport](https://registry.terraform.io/providers/CiscoDevNet/mso/1.1.0/docs/resources/schema_site_anp_epg_bulk_staticport) | resource |
| [mso_schema_site_anp_epg_domain.schema_site_anp_epg_domain_physical](https://registry.terraform.io/providers/CiscoDevNet/mso/1.1.0/docs/resources/schema_site_anp_epg_domain) | resource |
| [mso_schema_site_anp_epg_domain.schema_site_anp_epg_domain_vmware](https://registry.terraform.io/providers/CiscoDevNet/mso/1.1.0/docs/resources/schema_site_anp_epg_domain) | resource |
| [mso_schema_site_anp_epg_selector.schema_site_anp_epg_selector](https://registry.terraform.io/providers/CiscoDevNet/mso/1.1.0/docs/resources/schema_site_anp_epg_selector) | resource |
| [mso_schema_site_anp_epg_static_leaf.schema_site_anp_epg_static_leaf](https://registry.terraform.io/providers/CiscoDevNet/mso/1.1.0/docs/resources/schema_site_anp_epg_static_leaf) | resource |
| [mso_schema_site_anp_epg_subnet.schema_site_anp_epg_subnet](https://registry.terraform.io/providers/CiscoDevNet/mso/1.1.0/docs/resources/schema_site_anp_epg_subnet) | resource |
| [mso_schema_site_bd.schema_site_bd](https://registry.terraform.io/providers/CiscoDevNet/mso/1.1.0/docs/resources/schema_site_bd) | resource |
| [mso_schema_site_bd_l3out.schema_site_bd_l3out](https://registry.terraform.io/providers/CiscoDevNet/mso/1.1.0/docs/resources/schema_site_bd_l3out) | resource |
| [mso_schema_site_bd_subnet.schema_site_bd_subnet](https://registry.terraform.io/providers/CiscoDevNet/mso/1.1.0/docs/resources/schema_site_bd_subnet) | resource |
| [mso_schema_site_contract_service_graph.schema_site_contract_service_graph](https://registry.terraform.io/providers/CiscoDevNet/mso/1.1.0/docs/resources/schema_site_contract_service_graph) | resource |
| [mso_schema_site_external_epg_selector.schema_site_external_epg_selector](https://registry.terraform.io/providers/CiscoDevNet/mso/1.1.0/docs/resources/schema_site_external_epg_selector) | resource |
| [mso_schema_site_service_graph.schema_site_service_graph](https://registry.terraform.io/providers/CiscoDevNet/mso/1.1.0/docs/resources/schema_site_service_graph) | resource |
| [mso_schema_site_vrf.schema_site_vrf](https://registry.terraform.io/providers/CiscoDevNet/mso/1.1.0/docs/resources/schema_site_vrf) | resource |
| [mso_schema_site_vrf_region.schema_site_vrf_region](https://registry.terraform.io/providers/CiscoDevNet/mso/1.1.0/docs/resources/schema_site_vrf_region) | resource |
| [mso_schema_template_anp.schema_template_anp](https://registry.terraform.io/providers/CiscoDevNet/mso/1.1.0/docs/resources/schema_template_anp) | resource |
| [mso_schema_template_anp_epg.schema_template_anp_epg](https://registry.terraform.io/providers/CiscoDevNet/mso/1.1.0/docs/resources/schema_template_anp_epg) | resource |
| [mso_schema_template_anp_epg_contract.schema_template_anp_epg_contract](https://registry.terraform.io/providers/CiscoDevNet/mso/1.1.0/docs/resources/schema_template_anp_epg_contract) | resource |
| [mso_schema_template_anp_epg_subnet.schema_template_anp_epg_subnet](https://registry.terraform.io/providers/CiscoDevNet/mso/1.1.0/docs/resources/schema_template_anp_epg_subnet) | resource |
| [mso_schema_template_bd.schema_template_bd](https://registry.terraform.io/providers/CiscoDevNet/mso/1.1.0/docs/resources/schema_template_bd) | resource |
| [mso_schema_template_bd_subnet.schema_template_bd_subnet](https://registry.terraform.io/providers/CiscoDevNet/mso/1.1.0/docs/resources/schema_template_bd_subnet) | resource |
| [mso_schema_template_contract.schema_template_contract](https://registry.terraform.io/providers/CiscoDevNet/mso/1.1.0/docs/resources/schema_template_contract) | resource |
| [mso_schema_template_contract_service_graph.schema_template_contract_service_graph](https://registry.terraform.io/providers/CiscoDevNet/mso/1.1.0/docs/resources/schema_template_contract_service_graph) | resource |
| [mso_schema_template_deploy_ndo.template](https://registry.terraform.io/providers/CiscoDevNet/mso/1.1.0/docs/resources/schema_template_deploy_ndo) | resource |
| [mso_schema_template_deploy_ndo.template2](https://registry.terraform.io/providers/CiscoDevNet/mso/1.1.0/docs/resources/schema_template_deploy_ndo) | resource |
| [mso_schema_template_deploy_ndo.template3](https://registry.terraform.io/providers/CiscoDevNet/mso/1.1.0/docs/resources/schema_template_deploy_ndo) | resource |
| [mso_schema_template_external_epg.schema_template_external_epg](https://registry.terraform.io/providers/CiscoDevNet/mso/1.1.0/docs/resources/schema_template_external_epg) | resource |
| [mso_schema_template_external_epg_contract.schema_template_external_epg_contract](https://registry.terraform.io/providers/CiscoDevNet/mso/1.1.0/docs/resources/schema_template_external_epg_contract) | resource |
| [mso_schema_template_external_epg_selector.schema_template_external_epg_selector](https://registry.terraform.io/providers/CiscoDevNet/mso/1.1.0/docs/resources/schema_template_external_epg_selector) | resource |
| [mso_schema_template_external_epg_subnet.schema_template_external_epg_subnet](https://registry.terraform.io/providers/CiscoDevNet/mso/1.1.0/docs/resources/schema_template_external_epg_subnet) | resource |
| [mso_schema_template_filter_entry.schema_template_filter_entry](https://registry.terraform.io/providers/CiscoDevNet/mso/1.1.0/docs/resources/schema_template_filter_entry) | resource |
| [mso_schema_template_l3out.schema_template_l3out](https://registry.terraform.io/providers/CiscoDevNet/mso/1.1.0/docs/resources/schema_template_l3out) | resource |
| [mso_schema_template_service_graph.schema_template_service_graph](https://registry.terraform.io/providers/CiscoDevNet/mso/1.1.0/docs/resources/schema_template_service_graph) | resource |
| [mso_schema_template_vrf.schema_template_vrf](https://registry.terraform.io/providers/CiscoDevNet/mso/1.1.0/docs/resources/schema_template_vrf) | resource |
| [mso_schema_template_vrf_contract.schema_template_vrf_contract](https://registry.terraform.io/providers/CiscoDevNet/mso/1.1.0/docs/resources/schema_template_vrf_contract) | resource |
| [mso_site.site](https://registry.terraform.io/providers/CiscoDevNet/mso/1.1.0/docs/resources/site) | resource |
| [mso_tenant.tenant](https://registry.terraform.io/providers/CiscoDevNet/mso/1.1.0/docs/resources/tenant) | resource |
| [mso_rest.ndo_version](https://registry.terraform.io/providers/CiscoDevNet/mso/1.1.0/docs/data-sources/rest) | data source |
| [mso_rest.system_config](https://registry.terraform.io/providers/CiscoDevNet/mso/1.1.0/docs/data-sources/rest) | data source |
| [mso_schema.schema](https://registry.terraform.io/providers/CiscoDevNet/mso/1.1.0/docs/data-sources/schema) | data source |
| [mso_schema.template_schema](https://registry.terraform.io/providers/CiscoDevNet/mso/1.1.0/docs/data-sources/schema) | data source |
| [mso_site.site](https://registry.terraform.io/providers/CiscoDevNet/mso/1.1.0/docs/data-sources/site) | data source |
| [mso_site.template_site](https://registry.terraform.io/providers/CiscoDevNet/mso/1.1.0/docs/data-sources/site) | data source |
| [mso_site.tenant_site](https://registry.terraform.io/providers/CiscoDevNet/mso/1.1.0/docs/data-sources/site) | data source |
| [mso_tenant.template_tenant](https://registry.terraform.io/providers/CiscoDevNet/mso/1.1.0/docs/data-sources/tenant) | data source |
| [mso_user.tenant_user](https://registry.terraform.io/providers/CiscoDevNet/mso/1.1.0/docs/data-sources/user) | data source |
| [utils_yaml_merge.defaults](https://registry.terraform.io/providers/netascode/utils/latest/docs/data-sources/yaml_merge) | data source |
| [utils_yaml_merge.model](https://registry.terraform.io/providers/netascode/utils/latest/docs/data-sources/yaml_merge) | data source |

## Modules

No modules.
<!-- END_TF_DOCS -->