# Provisioning the POC on Azure with Terraform

Two stages, applied in order. Stage 1 builds the Azure footprint; stage 2
configures the Databricks workspace it created.

> **CI/CD:** state lives in an Azure Storage backend (see `backend.tf` +
> `bootstrap/README.md`), and GitHub Actions in `.github/workflows/` run
> `plan` on PRs and a gated `apply`/`destroy` via OIDC (no stored secrets).
> Do the one-time `bootstrap/README.md` steps before the pipeline can run.
> For purely local use, init with `-backend-config=backend.hcl` (also below).

```
terraform/
  1-foundation/   RG, VNet, 2 delegated Databricks subnets + VM subnet,
                  NSGs, NAT gateway, VNet-injected workspace (SCC/no-public-IP),
                  and a monitoring VM that auto-installs Docker and starts
                  Prometheus + Pushgateway + Grafana on boot.
  2-workspace/    Uploads the sink jar + init script and creates a single-node
                  cluster already pointed at the VM's Pushgateway.
```

```
                         one VNet (10.10.0.0/16)
 ┌───────────────────────────────────────────────────────────────────┐
 │  dbx-host /24 ┐                                                     │
 │               ├─ Databricks clusters (no public IP)                 │
 │  dbx-cont /24 ┘            │ push :9091 (intra-VNet)                │
 │                            ▼                                        │
 │  vm /28 ── monitoring VM (Pushgateway, Prometheus, Grafana)         │
 │                                                                     │
 │  NAT gateway ── egress for the Databricks subnets                   │
 └───────────────────────────────────────────────────────────────────┘
   SSH (your IP only) ─────────► VM public IP ──► tunnel Grafana/Prom
```

## Prerequisites

1. **Azure CLI logged in** — `az login`. Both stages authenticate through this
   (stage 2 needs no Databricks PAT).
2. **Subscription + permissions** to create the resources (Contributor on the
   subscription/RG is enough). VNet-injected workspaces use the **Premium**
   Databricks SKU.
3. **An SSH key pair** — point `ssh_public_key_path` at your public key.
4. **Your public IP** for SSH — `curl ifconfig.me`, set `admin_source_ip` to
   `<ip>/32`.
5. **The sink jar** at `databricks/lib/spark_metrics.jar` (see
   `databricks/lib/README.md`). Stage 2 uploads it.
6. **Keep the package folder structure intact** — stage 1 reads the real
   `docker/` files and stage 2 reads `databricks/` via relative paths.

## Stage 1 — Azure foundation + VM

```bash
cd terraform/1-foundation
cp terraform.tfvars.example terraform.tfvars   # fill in subscription_id, admin_source_ip, ssh key
terraform init
terraform apply
```

Note the outputs (`databricks_workspace_url`, `pushgateway_endpoint`,
`vm_public_ip`, `grafana_tunnel_hint`).

The VM installs Docker and starts the stack via cloud-init. Give it ~2–3
minutes after `apply` returns, then confirm:

```bash
ssh azureuser@<vm_public_ip>
sudo docker ps          # pushgateway, prometheus, grafana all running
```

## Stage 2 — Databricks workspace config

```bash
cd ../2-workspace
terraform init
terraform apply         # reads stage 1 state automatically
```

This uploads the jar + init script and creates the **DBX Observability POC**
cluster with `PROMETHEUS_HOST` already set to the VM's private `:9091`.

> If cluster creation errors on data-security mode (newer Unity-Catalog
> defaults), add `data_security_mode = "SINGLE_USER"` to the
> `databricks_cluster` resource and re-apply.

## Verify the loop

1. Tunnel to Grafana from your machine (from stage 1's `grafana_tunnel_hint`):
   ```bash
   ssh -L 3000:localhost:3000 -L 9090:localhost:9090 azureuser@<vm_public_ip>
   ```
   Open http://localhost:3000 (admin / admin). The **Databricks / Spark –
   Overview** dashboard is preloaded.
2. In Databricks, start the **DBX Observability POC** cluster and run any Spark
   workload (e.g. a Pi-estimation notebook).
3. Within ~10s the dashboard's **Pipeline health** row turns green and the
   JVM/Spark panels populate. If names differ, use Grafana Explore to confirm
   them (see the main `README.md` §5).

## Applying it to real job clusters

The single-node cluster is the demo target. For real coverage, attach the same
init script + the three `spark_env_vars` (`METRICS_JAR_PATH`,
`PROMETHEUS_HOST`, `PROMETHEUS_JOB_NAME`) to your actual job clusters — give
each job a distinct `PROMETHEUS_JOB_NAME` so you can filter by it in Grafana.

## Tear down

```bash
cd terraform/2-workspace && terraform destroy
cd ../1-foundation       && terraform destroy
```

## Cost note

Running ~24×7 this is roughly a small B2s VM + a Standard public IP + NAT
gateway (hourly + data) + the Databricks DBUs while a cluster is on. Stop the
cluster (auto-terminates in 30 min) and `destroy` when you're done to avoid
the NAT gateway and VM charges.
