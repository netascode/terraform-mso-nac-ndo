locals {
  fabric_connectivity = {
    controlPlaneBgpConfig = {
      peeringType            = try(local.ndo.fabric_connectivity.bgp.peering_type, local.defaults.ndo.fabric_connectivity.bgp.peering_type)
      ttl                    = try(local.ndo.fabric_connectivity.bgp.ttl, local.defaults.ndo.fabric_connectivity.bgp.ttl)
      keepAliveInterval      = try(local.ndo.fabric_connectivity.bgp.keepalive_interval, local.defaults.ndo.fabric_connectivity.bgp.keepalive_interval)
      holdInterval           = try(local.ndo.fabric_connectivity.bgp.hold_interval, local.defaults.ndo.fabric_connectivity.bgp.hold_interval)
      staleInterval          = try(local.ndo.fabric_connectivity.bgp.stale_interval, local.defaults.ndo.fabric_connectivity.bgp.stale_interval)
      gracefulRestartEnabled = try(local.ndo.fabric_connectivity.bgp.graceful_restart, local.defaults.ndo.fabric_connectivity.bgp.graceful_restart)
      maxAsLimit             = try(local.ndo.fabric_connectivity.bgp.max_as, local.defaults.ndo.fabric_connectivity.bgp.max_as)
    }
    sites = var.manage_site_connectivity ? [for site in try(local.ndo.sites, []) : {
      id                         = var.manage_sites ? mso_site.site[site.name].id : data.mso_site.site[site.name].id
      apicSiteId                 = site.id
      platform                   = "on-premise"
      fabricId                   = 1
      msiteEnabled               = try(site.multisite, local.defaults.ndo.sites.multisite)
      msiteDataPlaneMulticastTep = try(site.multicast_tep, "")
      bgpAsn                     = try(site.bgp.as, "")
      bgpPassword                = try(site.bgp.password, "")
      ospfAreaId                 = tostring(try(site.ospf.area_id, local.defaults.ndo.sites.ospf.area_id))
      ospfAreaType               = try(site.ospf.area_type, local.defaults.ndo.sites.ospf.area_type)
      externalRoutedDomain       = try(site.routed_domain, null) != null ? "uni/l3dom-${site.routed_domain}${local.defaults.ndo.sites.routed_domain_suffix}" : ""
      ospfPolicies = [for pol in try(site.ospf_policies, []) : {
        name               = "${pol.name}${local.defaults.ndo.sites.ospf_policies.name_suffix}"
        networkType        = try(pol.network_type, local.defaults.ndo.sites.ospf_policies.network_type)
        priority           = try(pol.priority, local.defaults.ndo.sites.ospf_policies.priority)
        interfaceCost      = try(pol.interface_cost, local.defaults.ndo.sites.ospf_policies.interface_cost)
        interfaceControls  = concat(try(pol.advertise_subnet, local.defaults.ndo.sites.ospf_policies.advertise_subnet) == true ? ["advertise-subnet"] : [], try(pol.bfd, local.defaults.ndo.sites.ospf_policies.bfd) == true ? ["bfd"] : [], try(pol.mtu_ignore, local.defaults.ndo.sites.ospf_policies.mtu_ignore) == true ? ["mtu-ignore"] : [], try(pol.passive_interface, local.defaults.ndo.sites.ospf_policies.passive_interface) == true ? ["passive-participation"] : [])
        helloInterval      = try(pol.hello_interval, local.defaults.ndo.sites.ospf_policies.hello_interval)
        deadInterval       = try(pol.dead_interval, local.defaults.ndo.sites.ospf_policies.dead_interval)
        retransmitInterval = try(pol.retransmit_interval, local.defaults.ndo.sites.ospf_policies.retransmit_interval)
        transmitDelay      = try(pol.retransmit_delay, local.defaults.ndo.sites.ospf_policies.retransmit_delay)
      }]
      pods = [for pod in try(site.pods, []) : {
        podId                          = try(pod.id, local.defaults.sites.pods.id)
        name                           = "pod-${try(pod.id, local.defaults.sites.pods.id)}"
        msiteDataPlaneUnicastTep       = try(pod.unicast_tep, "")
        msiteDataPlaneRoutableTEPPools = []
        faults                         = []
        spines = [for spine in try(pod.spines, []) : {
          nodeId                = spine.id
          name                  = spine.name
          bgpPeeringEnabled     = try(spine.bgp_peering, local.defaults.ndo.sites.pods.spines.bgp_peering)
          msiteControlPlaneTep  = spine.control_plane_tep
          routeReflectorEnabled = try(spine.bgp_route_reflector, local.defaults.ndo.sites.pods.spines.bgp_route_reflector)
          faults                = []
          ports = [for interface in try(spine.interfaces, []) : {
            portId        = "${try(interface.module, local.defaults.ndo.sites.pods.spines.interfaces.module)}/${interface.port}"
            ipAddress     = interface.ip
            mtu           = tostring(try(interface.mtu, local.defaults.ndo.sites.pods.spines.interfaces.mtu))
            routingPolicy = "${interface.ospf.policy}${local.defaults.ndo.sites.ospf_policies.name_suffix}"
            ospfAuthType  = try(interface.ospf.authentication_type, local.defaults.ndo.sites.pods.spines.interfaces.ospf.authentication_type)
            ospfAuthKey   = try(interface.ospf.authentication_key, "")
            ospfAuthKeyId = try(interface.ospf.authentication_key_id, local.defaults.ndo.sites.pods.spines.interfaces.ospf.authentication_key_id)
          }]
        }]
      }]
    }] : []
  }
}

data "mso_site" "site" {
  for_each = toset([for site in try(local.ndo.sites, []) : site.name if !var.manage_sites && var.manage_site_connectivity])
  name     = each.value
}

resource "mso_rest" "site_connectivity" {
  count   = var.manage_site_connectivity ? 1 : 0
  path    = "api/v1/sites/fabric-connectivity"
  method  = "PUT"
  payload = jsonencode(local.fabric_connectivity)
}
