module "site" {
  source  = "netascode/nac-ndo/mso"
  version = "0.1.0"

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
