locals {
  fabric_connectivity = {
    siteGroup = {
      common = {
        peeringType            = try(local.ndo.fabric_connectivity.bgp.peering_type, local.defaults.ndo.fabric_connectivity.bgp.peering_type, "full-mesh")
        ttl                    = try(local.ndo.fabric_connectivity.bgp.ttl, local.defaults.ndo.fabric_connectivity.bgp.ttl, 16)
        keepAliveInterval      = try(local.ndo.fabric_connectivity.bgp.keepalive_interval, local.defaults.ndo.fabric_connectivity.bgp.keepalive_interval, 60)
        holdInterval           = try(local.ndo.fabric_connectivity.bgp.hold_interval, local.defaults.ndo.fabric_connectivity.bgp.hold_interval, 180)
        staleInterval          = try(local.ndo.fabric_connectivity.bgp.stale_interval, local.defaults.ndo.fabric_connectivity.bgp.stale_interval, 300)
        gracefulRestartEnabled = try(local.ndo.fabric_connectivity.bgp.graceful_restart, local.defaults.ndo.fabric_connectivity.bgp.graceful_restart, "enabled") == "disabled" ? false : true
        maxAsLimit             = try(local.ndo.fabric_connectivity.bgp.max_as, local.defaults.ndo.fabric_connectivity.bgp.max_as, 0)
      }
      dcnm = { # The following defaults are required to ensure the API call succeeds
        l2VniRange          = "130000-149000"
        l3VniRange          = "150000-159000"
        msiteAnycastTepPool = "10.10.0.0/24"
        msiteAnycastMac     = "2020.0000.00aa"
      }
      # TODO: Add sites/pods resources
      sites = flatten([for site in try(local.ndo.sites, {}) : {
        id           = mso_site.site[site.name].id
        siteId       = site.id
        msiteEnabled = try(site.multisite, "enabled") == "disabled" ? false : true
      }])
    }
  }
}

resource "mso_rest" "site_connectivity" {
  count   = var.manage_site_connectivity ? 1 : 0
  path    = "api/v2/sites/fabric-connectivity"
  method  = "PUT"
  payload = jsonencode(local.fabric_connectivity)
}
