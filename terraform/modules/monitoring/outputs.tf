# terraform/modules/monitoring/outputs.tf

output "host" {
  description = "Primary IPv4 of nimbus-mon"
  value       = try(proxmox_virtual_environment_vm.mon.ipv4_addresses[1][0], "pending-guest-agent")
}

output "grafana_url" {
  description = "Grafana UI (reachable from mgmt subnet)"
  value       = "http://${split("/", var.static_ip)[0]}:3000"
}

output "prometheus_url" {
  description = "Prometheus UI (reachable from mgmt subnet)"
  value       = "http://${split("/", var.static_ip)[0]}:9090"
}

output "loki_url" {
  description = "Loki push endpoint (used by Promtail on each VM)"
  value       = "http://${split("/", var.static_ip)[0]}:3100"
}
