terraform {
  required_version = ">= 1.4.0"

  required_providers {
    mso = {
      source  = "CiscoDevNet/mso"
      version = ">= 0.9.0"
    }
    utils = {
      source  = "netascode/utils"
      version = ">= 0.2.4"
    }
    local = {
      source  = "hashicorp/local"
      version = ">= 2.3.0"
    }
  }
}
