module "tenant" {
  source  = "netascode/nac-ndo/mso"
  version = "0.1.0"

  yaml_files = ["ndo.yaml"]

  manage_sites   = true
  manage_tenants = true
}
