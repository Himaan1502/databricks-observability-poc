variable "subscription_id" {
  type        = string
  description = "Azure subscription ID to deploy into."
}

variable "prefix" {
  type        = string
  description = "Name prefix for all resources."
  default     = "dbxobs"
}

variable "location" {
  type        = string
  description = "Azure region. Must support Azure Databricks."
  default     = "Central India"
}

variable "resource_group_name" {
  type        = string
  description = "Resource group to create and deploy into."
  default     = "rg-dbx-observability-poc"
}

# --- Networking ------------------------------------------------------------
# VNet must be /16–/24. The two Databricks subnets must be at least /26 and
# cannot be shared with any other resource. The VM gets its own subnet.
variable "vnet_cidr" {
  type    = string
  default = "10.10.0.0/16"
}

variable "dbx_host_subnet_cidr" {
  type        = string
  description = "Databricks host (public) subnet."
  default     = "10.10.1.0/24"
}

variable "dbx_container_subnet_cidr" {
  type        = string
  description = "Databricks container (private) subnet."
  default     = "10.10.2.0/24"
}

variable "vm_subnet_cidr" {
  type        = string
  description = "Subnet for the monitoring VM."
  default     = "10.10.3.0/28"
}

variable "vm_private_ip" {
  type        = string
  description = "Static private IP for the VM (must be inside vm_subnet_cidr; Azure reserves the first 3 usable). This becomes the Pushgateway target."
  default     = "10.10.3.4"
}

# --- VM --------------------------------------------------------------------
variable "vm_size" {
  type    = string
  default = "Standard_B2s" # 2 vCPU / 4 GB – enough for prom+grafana+pushgateway
}

variable "ssh_public_key_path" {
  type        = string
  description = "Path to your SSH public key for VM access."
  default     = "~/.ssh/id_rsa.pub"
}

variable "admin_source_ip" {
  type        = string
  description = "Your public IP in CIDR form for SSH access, e.g. 203.0.113.10/32. Find it with: curl ifconfig.me"
}
