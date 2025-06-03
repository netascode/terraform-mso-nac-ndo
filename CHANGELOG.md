## 1.0.1 (unreleased)

- Fix handling of errors when merging invalid YAML content
- Fix incorrect merge of booleans in defaults file

## 1.0.0

- Add support for external TEP Pools
- Enhance contract filter chain with `policy_compression` attribute
- BREAKING CHANGE: Remove support for NDO 3.7
- Add support for NDO 4.3
- Add support for NDO 4.4
- Use Terraform functions to merge YAML content instead of data sources

## 0.9.3

- Add support for EP move detection mode under BD

## 0.9.2

- Enhance support for site-specific external EPGs
- Optimize retrieval of schema IDs
- Add support for FEX VPC static port configuration under EPG
- Add support for DHCP policies configuration under BD

## 0.9.1

- Add support for site-aware policy enforcement mode
- Add support for site-specific external EPG settings

## 0.9.0

- Add `custom_epg_name` attribute to EPG VMM domain

## 0.8.1

- Add support for NDO 4.2

## 0.8.0

- Add support for banner (`system_config`) configuration
- Add support for remote locations
- Add support for custom bridge domain MACs
- Add support for `no_default_gateway` and `primary` attributes to endpoint group subnets
- Switch from `mso_schema_site_anp_epg_static_port` to `mso_schema_site_anp_epg_bulk_staticport` resource
- Add `orchestrator_only` attribute to tenants
- Add `data_plane_learning` and `preferred_group` attributes to VRFs
- Add `multi_destination_flooding`, `unknown_ipv4_multicast` and `unknown_ipv6_multicast` attributes to bridge domains
- Add `node_type` attribute to service graph
- Add `type` attribute to template
- Add `description` attribute to template, bridge domain and endpoint group
- Support optional ordering of template deployment
- Add support for subport (breakout) EPG static ports

## 0.7.0

- Initial release
