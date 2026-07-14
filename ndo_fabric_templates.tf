locals {
  fabric_template_ids = { for template in try(jsondecode(data.mso_rest.templates.content), []) : template.templateName => { "id" : template.templateId } if template.templateType == "fabricPolicy" }
}

locals {
  fec_mode_map = {
    "disabled"       = "disable_fec"
    "cl91-rs-fec"    = "cl91_rs_fec"
    "cl74-fc-fec"    = "cl74_fc_fec"
    "auto-fec"       = "auto_fec"
    "ieee-rs-fec"    = "ieee_rs_fec"
    "cons16-rs-fec"  = "cons16_rs_fec"
    "inherit"        = "inherit"
  }
  qinq_map = {
    "disabled"       = "disabled"
    "edgePort"       = "edge_port"
    "corePort"       = "core_port"
    "doubleQtagPort" = "double_q_tag_port"
  }
  port_channel_mode_map = {
    "lacp-active"                     = "lacp_active"
    "lacp-passive"                    = "lacp_passive"
    "static-channel-mode-on"          = "static_channel_mode_on"
    "mac-pinning"                     = "mac_pinning"
    "mac-pinning-physical-nic-load"   = "mac_pinning_physical_nic_load"
    "use-explicit-failover-order"     = "use_explicit_failover_order"
  }
  load_balance_hashing_map = {
    "destination-ip"          = "destination_ip"
    "layer-4-destination-ip"  = "layer_4_destination_ip"
    "layer-4-source-ip"       = "layer_4_source_ip"
    "source-ip"               = "source_ip"
  }
  # macsec_cipher_suite_map = {
  #   "gcm-aes-128"     = "128GcmAes"
  #   "gcm-aes-256"     = "256GcmAes"
  #   "gcm-aes-xpn-128" = "128GcmAesXpn"
  #   "gcm-aes-xpn-256" = "256GcmAesXpn"
  # }
  # macsec_security_policy_map = {
  #   "should-secure" = "shouldSecure"
  #   "must-secure"   = "mustSecure"
  # }
}

locals {
  fabric_templates_sites = flatten(distinct([
    for template in local.fabric_templates : [
      for site in try(template.sites, []) : {
        key           = "${template.name}/${site}"
        template_name = template.name
        site_name     = site
      }
    ]
  ]))
}

data "mso_site" "fabric_templates_site" {
  for_each = toset(distinct([for site in local.fabric_templates_sites : site.site_name if(!var.manage_sites || local.ndo_platform_version == "4.1") && var.manage_fabric_templates]))
  name     = each.value
}

locals {
  fabric_policies = flatten([
    for template in local.fabric_templates : [{
      name  = template.name
      sites = [for site in try(template.sites, []) : var.manage_sites && local.ndo_platform_version != "4.1" ? mso_site.site[site].id : data.mso_site.fabric_templates_site[site].id]
    }]
  ])
}

resource "mso_template" "fabric_template" {
  for_each      = { for template in local.fabric_policies : template.name => template }
  template_name = each.value.name
  template_type = "fabric_policy"
  sites         = each.value.sites
}

locals {
  fabric_vlan_pools = flatten([
    for template in local.fabric_templates : [
      for pool in try(template.vlan_pools, []) : {
        key           = "${template.name}/${pool.name}"
        name          = pool.name
        template_name = template.name
        description   = try(pool.description, null)
        ranges = [for range in try(pool.ranges, []) : {
          from = range.from
          to   = range.to
        }]
      }
    ]
  ])
}

resource "mso_fabric_policies_vlan_pool" "fabric_policies_vlan_pool" {
  for_each    = { for pool in local.fabric_vlan_pools : pool.key => pool }
  template_id = mso_template.fabric_template[each.value.template_name].id
  name        = each.value.name
  description = each.value.description

  dynamic "vlan_range" {
    for_each = each.value.ranges
    content {
      from = vlan_range.value.from
      to   = vlan_range.value.to
    }
  }
}

locals {
  fabric_physical_domains = flatten([
    for template in local.fabric_templates : [
      for domain in try(template.physical_domains, []) : {
        key           = "${template.name}/${domain.name}"
        name          = domain.name
        template_name = template.name
        description   = try(domain.description, null)
        vlan_pool     = "${template.name}/${domain.vlan_pool}"
      }
    ]
  ])
}

resource "mso_fabric_policies_physical_domain" "fabric_policies_physical_domain" {
  for_each       = { for domain in local.fabric_physical_domains : domain.key => domain }
  template_id    = mso_template.fabric_template[each.value.template_name].id
  name           = each.value.name
  description    = each.value.description
  vlan_pool_uuid = mso_fabric_policies_vlan_pool.fabric_policies_vlan_pool[each.value.vlan_pool].uuid

  depends_on = [mso_fabric_policies_vlan_pool.fabric_policies_vlan_pool]
}

locals {
  fabric_l3_domains = flatten([
    for template in local.fabric_templates : [
      for domain in try(template.l3_domains, []) : {
        key           = "${template.name}/${domain.name}"
        name          = domain.name
        template_name = template.name
        description   = try(domain.description, null)
        vlan_pool     = "${template.name}/${domain.vlan_pool}"
      }
    ]
  ])
}

resource "mso_fabric_policies_l3_domain" "fabric_policies_l3_domain" {
  for_each       = { for domain in local.fabric_l3_domains : domain.key => domain }
  template_id    = mso_template.fabric_template[each.value.template_name].id
  name           = each.value.name
  description    = each.value.description
  vlan_pool_uuid = mso_fabric_policies_vlan_pool.fabric_policies_vlan_pool[each.value.vlan_pool].uuid

  depends_on = [mso_fabric_policies_vlan_pool.fabric_policies_vlan_pool]
}

locals {
  fabric_mcp_global_policies = flatten([
    for template in local.fabric_templates : [{
      key                               = template.name
      template_name                     = template.name
      name                              = try(template.mcp_global_policy.name, null)
      description                       = try(template.mcp_global_policy.description, null)
      admin_state                       = try(template.mcp_global_policy.admin_state, local.defaults.ndo.fabric_templates.fabric_policies.mcp_global_policy.admin_state) ? "enabled" : "disabled"
      enable_mcp_pdu_per_vlan           = try(template.mcp_global_policy.enable_mcp_pdu_per_vlan, local.defaults.ndo.fabric_templates.fabric_policies.mcp_global_policy.enable_mcp_pdu_per_vlan) ? "enabled" : "disabled"
      key_value                         = try(template.mcp_global_policy.key, null)
      loop_detect_multiplication_factor = try(template.mcp_global_policy.loop_detection, local.defaults.ndo.fabric_templates.fabric_policies.mcp_global_policy.loop_detection)
      port_disable_protection           = try(template.mcp_global_policy.port_disable_protection, local.defaults.ndo.fabric_templates.fabric_policies.mcp_global_policy.port_disable_protection) ? "enabled" : "disabled"
      initial_delay_time                = try(template.mcp_global_policy.initial_delay, local.defaults.ndo.fabric_templates.fabric_policies.mcp_global_policy.initial_delay)
      transmission_frequency_sec        = try(template.mcp_global_policy.transmission_frequency_sec, local.defaults.ndo.fabric_templates.fabric_policies.mcp_global_policy.transmission_frequency_sec)
      transmission_frequency_msec       = try(template.mcp_global_policy.transmission_frequency_msec, local.defaults.ndo.fabric_templates.fabric_policies.mcp_global_policy.transmission_frequency_msec)
    }] if try(template.mcp_global_policy, null) != null
  ])
}

resource "mso_fabric_policies_mcp_global_policy" "fabric_policies_mcp_global_policy" {
  for_each                          = { for policy in local.fabric_mcp_global_policies : policy.key => policy }
  template_id                       = mso_template.fabric_template[each.value.template_name].id
  name                              = each.value.name
  description                       = each.value.description
  admin_state                       = each.value.admin_state
  enable_mcp_pdu_per_vlan           = each.value.enable_mcp_pdu_per_vlan
  key                               = each.value.key_value
  loop_detect_multiplication_factor = each.value.loop_detect_multiplication_factor
  port_disable_protection           = each.value.port_disable_protection
  initial_delay_time                = each.value.initial_delay_time
  transmission_frequency_sec        = each.value.transmission_frequency_sec
  transmission_frequency_msec       = each.value.transmission_frequency_msec
}

# locals {
#   fabric_macsec_policies = flatten([
#     for template in local.fabric_templates : [
#       for policy in try(template.macsec_policies, []) : {
#         key                    = "${template.name}/${policy.name}"
#         name                   = policy.name
#         template_name          = template.name
#         description            = try(policy.description, null)
#         admin_state            = try(policy.admin_state, local.defaults.ndo.fabric_templates.fabric_policies.macsec_policies.admin_state) ? "enabled" : "disabled"
#         interface_type         = try(policy.type, local.defaults.ndo.fabric_templates.fabric_policies.macsec_policies.type)
#         cipher_suite           = replace(replace(replace(replace(try(policy.cipher_suite, local.defaults.ndo.fabric_templates.fabric_policies.macsec_policies.cipher_suite), "gcm-aes-xpn-256", "256GcmAesXpn"), "gcm-aes-xpn-128", "128GcmAesXpn"), "gcm-aes-256", "256GcmAes"), "gcm-aes-128", "128GcmAes")
#         window_size            = try(policy.window_size, local.defaults.ndo.fabric_templates.fabric_policies.macsec_policies.window_size)
#         security_policy        = replace(replace(try(policy.security_policy, local.defaults.ndo.fabric_templates.fabric_policies.macsec_policies.security_policy), "should-secure", "shouldSecure"), "must-secure", "mustSecure")
#         sak_expire_time        = try(policy.sak_expiry_time, local.defaults.ndo.fabric_templates.fabric_policies.macsec_policies.sak_expiry_time)
#         confidentiality_offset = try(policy.confidentiality_offset, local.defaults.ndo.fabric_templates.fabric_policies.macsec_policies.confidentiality_offset)
#         key_server_priority    = try(policy.key_server_priority, local.defaults.ndo.fabric_templates.fabric_policies.macsec_policies.key_server_priority)
#         macsec_keys = [for key in try(policy.keys, []) : {
#           key_name   = key.key_name
#           psk        = key.pre_shared_key
#           start_time = try(key.start_time, local.defaults.ndo.fabric_templates.fabric_policies.macsec_policies.keys.start_time)
#           end_time   = try(key.end_time, local.defaults.ndo.fabric_templates.fabric_policies.macsec_policies.keys.end_time)
#         }]
#       }
#     ]
#   ])
# }

# resource "mso_fabric_policies_macsec_policy" "fabric_policies_macsec_policy" {
#   for_each               = { for policy in local.fabric_macsec_policies : policy.key => policy }
#   template_id            = mso_template.fabric_template[each.value.template_name].id
#   name                   = each.value.name
#   description            = each.value.description
#   admin_state            = each.value.admin_state
#   interface_type         = each.value.interface_type
#   cipher_suite           = each.value.cipher_suite
#   window_size            = each.value.window_size
#   security_policy        = each.value.security_policy
#   sak_expire_time        = each.value.sak_expire_time
#   confidentiality_offset = each.value.confidentiality_offset
#   key_server_priority    = each.value.key_server_priority
#
#   dynamic "macsec_keys" {
#     for_each = each.value.macsec_keys
#     content {
#       key_name   = macsec_keys.value.key_name
#       psk        = macsec_keys.value.psk
#       start_time = macsec_keys.value.start_time
#       end_time   = macsec_keys.value.end_time
#     }
#   }
# }

locals {
  fabric_synce_interface_policies = flatten([
    for template in local.fabric_templates : [
      for policy in try(template.synce_interface_policies, []) : {
        key             = "${template.name}/${policy.name}"
        name            = policy.name
        template_name   = template.name
        description     = try(policy.description, null)
        admin_state     = try(policy.admin_state, local.defaults.ndo.fabric_templates.fabric_policies.synce_interface_policies.admin_state) ? "enabled" : "disabled"
        sync_state_msg  = try(policy.sync_state_message, local.defaults.ndo.fabric_templates.fabric_policies.synce_interface_policies.sync_state_message) ? "enabled" : "disabled"
        selection_input = try(policy.selection_input, local.defaults.ndo.fabric_templates.fabric_policies.synce_interface_policies.selection_input) ? "enabled" : "disabled"
        src_priority    = try(policy.source_priority, local.defaults.ndo.fabric_templates.fabric_policies.synce_interface_policies.source_priority)
        wait_to_restore = try(policy.wait_to_restore, local.defaults.ndo.fabric_templates.fabric_policies.synce_interface_policies.wait_to_restore)
      }
    ]
  ])
}

resource "mso_fabric_policies_synce_interface_policy" "fabric_policies_synce_interface_policy" {
  for_each        = { for policy in local.fabric_synce_interface_policies : policy.key => policy }
  template_id     = mso_template.fabric_template[each.value.template_name].id
  name            = each.value.name
  description     = each.value.description
  admin_state     = each.value.admin_state
  sync_state_msg  = each.value.sync_state_msg
  selection_input = each.value.selection_input
  src_priority    = each.value.src_priority
  wait_to_restore = each.value.wait_to_restore
}

locals {
  fabric_interface_settings = flatten([
    for template in local.fabric_templates : [
      for intf in try(template.interfaces_settings, []) : {
        key                             = "${template.name}/${intf.name}"
        name                            = intf.name
        template_name                   = template.name
        description                     = try(intf.description, null)
        type                            = try(intf.type, local.defaults.ndo.fabric_templates.fabric_policies.interfaces_settings.type) == "port-channel" ? "portchannel" : "physical"
        speed                           = try(intf.link_level.speed, local.defaults.ndo.fabric_templates.fabric_policies.interfaces_settings.link_level.speed)
        auto_negotiation                = try(intf.link_level.auto_enforce, local.defaults.ndo.fabric_templates.fabric_policies.interfaces_settings.link_level.auto_enforce) ? "on_enforce" : try(intf.link_level.auto, local.defaults.ndo.fabric_templates.fabric_policies.interfaces_settings.link_level.auto) ? "on" : "off"
        link_level_debounce_interval    = try(intf.link_level.debounce_interval, local.defaults.ndo.fabric_templates.fabric_policies.interfaces_settings.link_level.debounce_interval)
        link_level_bring_up_delay       = try(intf.link_level.bring_up_delay, local.defaults.ndo.fabric_templates.fabric_policies.interfaces_settings.link_level.bring_up_delay)
        link_level_fec                  = local.fec_mode_map[try(intf.link_level.fec_mode, local.defaults.ndo.fabric_templates.fabric_policies.interfaces_settings.link_level.fec_mode)]
        vlan_scope                      = try(intf.l2_interface.vlan_scope, local.defaults.ndo.fabric_templates.fabric_policies.interfaces_settings.l2_interface.vlan_scope)
        l2_interface_qinq               = local.qinq_map[try(intf.l2_interface.qinq, local.defaults.ndo.fabric_templates.fabric_policies.interfaces_settings.l2_interface.qinq)]
        l2_interface_reflective_relay   = try(intf.l2_interface.reflective_relay, local.defaults.ndo.fabric_templates.fabric_policies.interfaces_settings.l2_interface.reflective_relay) ? "enabled" : "disabled"
        cdp_admin_state                 = try(intf.cdp.admin_state, local.defaults.ndo.fabric_templates.fabric_policies.interfaces_settings.cdp.admin_state) ? "enabled" : "disabled"
        lldp_receive_state              = try(intf.lldp.receive_state, local.defaults.ndo.fabric_templates.fabric_policies.interfaces_settings.lldp.receive_state) ? "enabled" : "disabled"
        lldp_transmit_state             = try(intf.lldp.transmit_state, local.defaults.ndo.fabric_templates.fabric_policies.interfaces_settings.lldp.transmit_state) ? "enabled" : "disabled"
        stp_bpdu_filter                 = try(intf.stp.bpdu_filter, local.defaults.ndo.fabric_templates.fabric_policies.interfaces_settings.stp.bpdu_filter) ? "enabled" : "disabled"
        stp_bpdu_guard                  = try(intf.stp.bpdu_guard, local.defaults.ndo.fabric_templates.fabric_policies.interfaces_settings.stp.bpdu_guard) ? "enabled" : "disabled"
        llfc_transmit_state             = try(intf.llfc.transmit_state, local.defaults.ndo.fabric_templates.fabric_policies.interfaces_settings.llfc.transmit_state) ? "enabled" : "disabled"
        llfc_receive_state              = try(intf.llfc.receive_state, local.defaults.ndo.fabric_templates.fabric_policies.interfaces_settings.llfc.receive_state) ? "enabled" : "disabled"
        mcp_admin_state                 = try(intf.mcp.admin_state, local.defaults.ndo.fabric_templates.fabric_policies.interfaces_settings.mcp.admin_state) ? "enabled" : "disabled"
        mcp_strict_mode                 = try(intf.mcp.strict_mode, local.defaults.ndo.fabric_templates.fabric_policies.interfaces_settings.mcp.strict_mode) ? "on" : "off"
        mcp_initial_delay_time          = try(intf.mcp.initial_delay_time, local.defaults.ndo.fabric_templates.fabric_policies.interfaces_settings.mcp.initial_delay_time)
        mcp_transmission_frequency_sec  = try(intf.mcp.transmission_frequency_sec, local.defaults.ndo.fabric_templates.fabric_policies.interfaces_settings.mcp.transmission_frequency_sec)
        mcp_transmission_frequency_msec = try(intf.mcp.transmission_frequency_msec, local.defaults.ndo.fabric_templates.fabric_policies.interfaces_settings.mcp.transmission_frequency_msec)
        mcp_grace_period_sec            = try(intf.mcp.grace_period_sec, local.defaults.ndo.fabric_templates.fabric_policies.interfaces_settings.mcp.grace_period_sec)
        mcp_grace_period_msec           = try(intf.mcp.grace_period_msec, local.defaults.ndo.fabric_templates.fabric_policies.interfaces_settings.mcp.grace_period_msec)
        pfc_admin_state                 = try(intf.pfc.admin_state, local.defaults.ndo.fabric_templates.fabric_policies.interfaces_settings.pfc.admin_state) ? (try(intf.pfc.auto, local.defaults.ndo.fabric_templates.fabric_policies.interfaces_settings.pfc.auto) ? "auto" : "on") : "off"
        port_channel_mode               = local.port_channel_mode_map[try(intf.port_channel.mode, local.defaults.ndo.fabric_templates.fabric_policies.interfaces_settings.port_channel.mode)]
        port_channel_controls = toset(concat(
          try(intf.port_channel.suspend_individual, local.defaults.ndo.fabric_templates.fabric_policies.interfaces_settings.port_channel.suspend_individual) ? ["susp_individual"] : [],
          try(intf.port_channel.graceful_convergence, local.defaults.ndo.fabric_templates.fabric_policies.interfaces_settings.port_channel.graceful_convergence) ? ["graceful_conv"] : [],
          try(intf.port_channel.fast_select_standby, local.defaults.ndo.fabric_templates.fabric_policies.interfaces_settings.port_channel.fast_select_standby) ? ["fast_sel_hot_stdby"] : [],
          try(intf.port_channel.load_defer, local.defaults.ndo.fabric_templates.fabric_policies.interfaces_settings.port_channel.load_defer) ? ["load_defer"] : [],
          try(intf.port_channel.symmetric_hash, local.defaults.ndo.fabric_templates.fabric_policies.interfaces_settings.port_channel.symmetric_hash) ? ["symmetric_hash"] : [],
        ))
        port_channel_min_links        = try(intf.port_channel.min_links, local.defaults.ndo.fabric_templates.fabric_policies.interfaces_settings.port_channel.min_links)
        port_channel_max_links        = try(intf.port_channel.max_links, local.defaults.ndo.fabric_templates.fabric_policies.interfaces_settings.port_channel.max_links)
        load_balance_hashing          = try(intf.port_channel.load_balance_hashing, null) != null ? local.load_balance_hashing_map[intf.port_channel.load_balance_hashing] : null
        synce_uuid_key                = try(intf.synce_policy, null) != null ? "${template.name}/${intf.synce_policy}" : null
        domain_uuid_keys              = [for domain in try(intf.domains, []) : "${template.name}/${domain}"]
        access_macsec_policy_uuid_key = null # try(intf.macsec_interface_policy, null) != null ? "${template.name}/${intf.macsec_interface_policy}" : null
      }
    ]
  ])
}

resource "mso_fabric_policies_interface_setting" "fabric_policies_interface_setting" {
  for_each                        = { for intf in local.fabric_interface_settings : intf.key => intf }
  template_id                     = mso_template.fabric_template[each.value.template_name].id
  name                            = each.value.name
  description                     = each.value.description
  type                            = each.value.type
  speed                           = each.value.speed
  auto_negotiation                = each.value.auto_negotiation
  link_level_debounce_interval    = each.value.link_level_debounce_interval
  link_level_bring_up_delay       = each.value.link_level_bring_up_delay
  link_level_fec                  = each.value.link_level_fec
  vlan_scope                      = each.value.vlan_scope
  l2_interface_qinq               = each.value.l2_interface_qinq
  l2_interface_reflective_relay   = each.value.l2_interface_reflective_relay
  cdp_admin_state                 = each.value.cdp_admin_state
  lldp_receive_state              = each.value.lldp_receive_state
  lldp_transmit_state             = each.value.lldp_transmit_state
  stp_bpdu_filter                 = each.value.stp_bpdu_filter
  stp_bpdu_guard                  = each.value.stp_bpdu_guard
  llfc_transmit_state             = each.value.llfc_transmit_state
  llfc_receive_state              = each.value.llfc_receive_state
  mcp_admin_state                 = each.value.mcp_admin_state
  mcp_strict_mode                 = each.value.mcp_admin_state == "enabled" ? each.value.mcp_strict_mode : null
  mcp_initial_delay_time          = each.value.mcp_admin_state == "enabled" ? each.value.mcp_initial_delay_time : null
  mcp_transmission_frequency_sec  = each.value.mcp_admin_state == "enabled" ? each.value.mcp_transmission_frequency_sec : null
  mcp_transmission_frequency_msec = each.value.mcp_admin_state == "enabled" ? each.value.mcp_transmission_frequency_msec : null
  mcp_grace_period_sec            = each.value.mcp_admin_state == "enabled" ? each.value.mcp_grace_period_sec : null
  mcp_grace_period_msec           = each.value.mcp_admin_state == "enabled" ? each.value.mcp_grace_period_msec : null
  pfc_admin_state                 = each.value.pfc_admin_state
  port_channel_mode               = each.value.type == "portchannel" ? each.value.port_channel_mode : null
  controls                        = each.value.type == "portchannel" ? each.value.port_channel_controls : null
  port_channel_min_links          = each.value.type == "portchannel" ? each.value.port_channel_min_links : null
  port_channel_max_links          = each.value.type == "portchannel" ? each.value.port_channel_max_links : null
  load_balance_hashing            = each.value.type == "portchannel" ? each.value.load_balance_hashing : null
  synce_uuid                      = each.value.synce_uuid_key != null ? mso_fabric_policies_synce_interface_policy.fabric_policies_synce_interface_policy[each.value.synce_uuid_key].uuid : null
  domain_uuids                    = length(each.value.domain_uuid_keys) > 0 ? toset([for key in each.value.domain_uuid_keys : try(mso_fabric_policies_physical_domain.fabric_policies_physical_domain[key].uuid, mso_fabric_policies_l3_domain.fabric_policies_l3_domain[key].uuid)]) : null
  access_macsec_policy_uuid       = null # each.value.access_macsec_policy_uuid_key != null ? mso_fabric_policies_macsec_policy.fabric_policies_macsec_policy[each.value.access_macsec_policy_uuid_key].uuid : null

  depends_on = [
    mso_fabric_policies_synce_interface_policy.fabric_policies_synce_interface_policy,
    # mso_fabric_policies_macsec_policy.fabric_policies_macsec_policy,
    mso_fabric_policies_physical_domain.fabric_policies_physical_domain,
    mso_fabric_policies_l3_domain.fabric_policies_l3_domain,
  ]
}
