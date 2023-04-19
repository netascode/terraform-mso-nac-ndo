variable "yaml_directories" {
  description = "List of paths to YAML directories."
  type        = list(string)
  default     = []
}

variable "yaml_files" {
  description = "List of paths to YAML files."
  type        = list(string)
  default     = []
}

variable "model" {
  description = "As an alternative to YAML files, a native Terraform data structure can be provided as well."
  type        = map(any)
  default     = {}
}

# tflint-ignore: terraform_unused_declarations
variable "manage_system" {
  description = "Flag to indicate if system level configuration should be managed."
  type        = bool
  default     = false
}

variable "manage_sites" {
  description = "Flag to indicate if sites should be managed."
  type        = bool
  default     = false
}

variable "manage_site_connectivity" {
  description = "Flag to indicate if site connectivity be managed."
  type        = bool
  default     = false
}

variable "manage_tenants" {
  description = "Flag to indicate if tenants be managed."
  type        = bool
  default     = false
}

variable "managed_tenants" {
  description = "List of tenant names to be managed. By default all tenants will be managed."
  type        = list(string)
  default     = []
}

variable "manage_schemas" {
  description = "Flag to indicate if schemas should be managed."
  type        = bool
  default     = false
}

variable "managed_schemas" {
  description = "List of schema names to be managed. By default all schemas will be managed."
  type        = list(string)
  default     = []
}

variable "deploy_templates" {
  description = "Flag to indicate if templates should be deployed."
  type        = bool
  default     = false
}

variable "write_default_values_file" {
  description = "Write all default values to a YAML file. Value is a path pointing to the file to be created."
  type        = string
  default     = ""
}
