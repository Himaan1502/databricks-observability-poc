output "databricks_workspace_url" {
  description = "Workspace URL (used by stage 2's databricks provider)."
  value       = "https://${azurerm_databricks_workspace.this.workspace_url}"
}

output "databricks_workspace_id" {
  description = "Workspace ARM resource ID (used by stage 2 for Azure auth)."
  value       = azurerm_databricks_workspace.this.id
}

output "pushgateway_endpoint" {
  description = "host:port the cluster pushes metrics to (VM private IP)."
  value       = "${var.vm_private_ip}:9091"
}

output "vm_public_ip" {
  description = "SSH here; tunnel Grafana/Prometheus through it."
  value       = azurerm_public_ip.vm.ip_address
}

output "grafana_tunnel_hint" {
  value = "ssh -L 3000:localhost:3000 -L 9090:localhost:9090 azureuser@${azurerm_public_ip.vm.ip_address}  # then open http://localhost:3000"
}
