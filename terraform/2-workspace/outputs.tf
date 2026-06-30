output "cluster_id" {
  value = databricks_cluster.demo.id
}

output "pushgateway_target" {
  description = "Where the cluster is pushing metrics."
  value       = local.pushgateway_host
}

output "next_step" {
  value = "Start the 'DBX Observability POC' cluster, run any Spark workload, then watch the Grafana dashboard (tunnel from the VM)."
}
