variable "prometheus_pushgateway_host" {
  type        = string
  description = "host:port of the Pushgateway the cluster pushes to, e.g. 10.0.0.5:9091"
}

# Optional – only needed if you also enable the Pyroscope (APM) path.
variable "pyroscope_host" {
  type        = string
  description = "host:port of the Pyroscope server, e.g. 10.0.0.5:4040"
  default     = ""
}
