terraform {
  required_version = ">= 1.8.0"

  required_providers {
    mso = {
      source  = "CiscoDevNet/mso"
      version = ">= 3.1.0"
    }
    utils = {
      source  = "netascode/utils"
      version = "~> 2.0.0"
    }
    local = {
      source  = "hashicorp/local"
      version = ">= 2.3.0"
    }
  }
}
