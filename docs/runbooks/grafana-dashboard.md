# Nimbus Grafana Dashboard

Nimbus ships a Grafana dashboard for the AWS-style infrastructure map in this
repo:

- Source JSON: `terraform/modules/monitoring/dashboards/nimbus-aws-infrastructure.json`
- Provisioned path on `nimbus-mon`: `/var/lib/grafana/dashboards/nimbus-aws-infrastructure.json`
- Grafana folder: `Nimbus`
- Dashboard title: `Nimbus AWS-Style Infrastructure`

## Terraform-managed install

For a new or intentionally rebuilt `nimbus-mon`, the monitoring module
provisions the dashboard automatically through cloud-init:

```bash
cd terraform
terraform apply
```

If `nimbus-mon` already exists, `terraform apply` updates the Proxmox
user-data snippet but does not re-run cloud-init inside the VM. Use manual
import for the existing Grafana instance, or intentionally rebuild the
monitoring VM:

```bash
cd terraform
terraform apply -replace=module.nimbus_mon.proxmox_virtual_environment_vm.mon
```

Rebuilding `nimbus-mon` replaces the VM disk, so export anything you need from
Grafana, Prometheus, or Loki first.

Grafana is reachable through the existing monitoring output:

```bash
terraform output nimbus_mon_grafana_url
```

## Manual import

In another Grafana instance, import the dashboard JSON directly. The dashboard
expects these data source UIDs:

| Data source | Type       | UID          |
|-------------|------------|--------------|
| Prometheus  | Prometheus | `prometheus` |
| Loki        | Loki       | `loki`       |

The Terraform-provisioned `nimbus-mon` data sources already use those UIDs.

## Current telemetry coverage

The dashboard uses the telemetry already present in the repo:

- Prometheus scrapes `node-exporter` on all Nimbus VMs.
- Loki receives Promtail logs with the `host` label.
- Panels cover node health, CPU, memory, filesystem, disk IO, network IO,
  uptime, clock skew, recent logs, auth failures, and error/warning log rates.

Service-level panels for HAProxy, PostgreSQL, MinIO, and PowerDNS need those
exporters enabled first. Until then, the dashboard shows host-level and log
signals for those AWS-equivalent services.
