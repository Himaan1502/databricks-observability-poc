variable "prometheus_pushgateway_host" {
  type        = string
  description = "Override the Pushgateway host:port. Leave empty to use the VM endpoint from stage 1."
  default     = ""
}

variable "job_name" {
  type        = string
  description = "Value of the job_name metric label."
  default     = "dbx-poc-interactive"
}

# --- Coordinates of the shared state backend (to read stage 1's outputs) ---
variable "state_resource_group_name" {
  type        = string
  description = "Resource group of the Terraform state storage account."
}

variable "state_storage_account_name" {
  type        = string
  description = "Terraform state storage account name."
}

variable "state_container_name" {
  type    = string
  default = "tfstate"
}
