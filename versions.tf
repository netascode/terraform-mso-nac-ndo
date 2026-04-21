terraform {
  required_version = ">= 1.8.0"

  required_providers {
    mso = {
      source  = "CiscoDevNet/mso"
      version = ">= 2.0.0"
    }
    utils = {
      source  = "netascode/utils"
      version = "= 2.0.0-beta2"
    }
    local = {
      source  = "hashicorp/local"
      version = ">= 2.3.0"
    }
  }
}
