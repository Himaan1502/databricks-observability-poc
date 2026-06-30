# Databricks Observability POC — Grafana + Prometheus

A self-contained proof-of-concept for collecting **Apache Spark metrics from
Databricks** into **Prometheus** and visualizing them in **Grafana**, based on
the Databricks Community blog *"Databricks Observability using Grafana and
Prometheus"* and its companion repo
[`rayalex/spark-databricks-observability`](https://github.com/rayalex/spark-databricks-observability).

This package improves on the blog with: env-var-driven (re-usable) init script,
provider-agnostic auth, an **auto-provisioned Grafana datasource + dashboard**
(the upstream repo ships only screenshots), a PromQL starter set, a metric-name
discovery procedure, and production-hardening notes.

---

## 1. How it works

Prometheus is **pull-based**: it scrapes a stable HTTP endpoint on a schedule.
That suits long-running services but not Databricks **jobs**, which are
ephemeral — a job cluster spins up, runs, and disappears, so there's nothing
stable for Prometheus to scrape. The fix is to **invert the flow for the
short-lived side**: each Spark JVM *pushes* its metrics to a **Pushgateway**,
which holds them; Prometheus then scrapes the (always-on) Pushgateway.

```
   Databricks workspace                         Monitoring host (this stack)
 ┌───────────────────────────┐
 │  Spark cluster / job      │
 │                           │   push (every 5s, HTTP)
 │   ┌─────────┐             │        :9091
 │   │ Driver  │──────────────────────────────►┌──────────────┐
 │   └─────────┘             │                  │ Pushgateway  │
 │   ┌─────────┐             │                  └──────┬───────┘
 │   │Executor │──────────────────────────────►       │ scrape :9091 (every 5s)
 │   └─────────┘             │                         ▼
 │   ┌─────────┐             │                  ┌──────────────┐
 │   │Executor │─────────────┘                  │ Prometheus   │
 │   └─────────┘                                └──────┬───────┘
 │   init script wires Spark's metrics                 │ query :9090
 │   system -> PrometheusSink                          ▼
 └───────────────────────────┘                  ┌──────────────┐
                                                 │   Grafana    │  :3000
                                                 └──────────────┘
```

The four moving parts:

1. **`spark-metrics` (banzaicloud) sink** — a JVM library (`PrometheusSink`
   class) that plugs into Spark's built-in metrics subsystem. Spark already
   emits a rich Dropwizard metric registry (JVM heap, GC, DAG scheduler,
   executors, BlockManager, shuffle, …); the sink serializes those and pushes
   them to Pushgateway. The PR to merge a Prometheus sink upstream into Spark
   was never accepted, which is why this externalized library exists. The jar
   used here is built for Spark 3.5 / Scala 2.12.

2. **Init script** (`databricks/init-prometheus.sh`) — a cluster-scoped script
   that runs on every node *before* the Spark JVM starts. It copies the sink
   jar onto the classpath and writes `metrics.properties` so Spark loads the
   sink on boot. It reads three cluster **environment variables**
   (`METRICS_JAR_PATH`, `PROMETHEUS_HOST`, `PROMETHEUS_JOB_NAME`) so the same
   script is reusable across clusters/jobs without editing.

3. **Pushgateway** — receives and caches pushed metrics so Prometheus has a
   stable target. `enable-hostname-in-instance=true` means each executor shows
   up with its own `instance` label, so they don't overwrite each other.

4. **Prometheus + Grafana** — Prometheus scrapes Pushgateway every 5s and
   stores the time series; Grafana queries Prometheus and renders dashboards.

> A second, optional pillar — **continuous profiling / APM with Pyroscope** —
> is the subject of the blog's "part 2". The hooks are included (commented
> Pyroscope service, `init-pyroscope.sh` equivalent, `spark.plugins` settings)
> but are not required for the Grafana+Prometheus POC.

---

## 2. Is this native to Databricks, or open source?

**The blog's stack is 100% open source** (Prometheus, Pushgateway, Grafana,
Pyroscope are all Apache/AGPL OSS; the sink is Apache-2.0). Databricks does
**not** ship this exact pipeline as a managed product — it's a
bring-your-own-tooling pattern, authored by a Databricks employee but assembled
from OSS. What Databricks *does* offer natively (per the official docs) falls
into three buckets, summarized below so you can decide what's worth building
vs. using off the shelf:

| Need | Native Databricks option | Prometheus/Grafana export? |
|---|---|---|
| Quick look at cluster hardware + Spark metrics | **Compute Metrics UI** — built-in *Metrics* tab on all-purpose & jobs compute, near-real-time (<1 min), stored in Databricks-managed storage. Serverless uses *Query Insights* instead. | No — it's a built-in UI, not scrapeable |
| Monitor **Model Serving** endpoints | **Native Prometheus endpoint**: `GET /api/2.0/serving-endpoints/<name>/metrics` returns OpenMetrics text (cpu/mem %, request counts, latency histograms) | **Yes** — scrapeable by Prometheus/Datadog, but *only* for serving endpoints |
| Scrape **general Spark cluster** metrics with Prometheus | Spark 3.0+ ships a native **`PrometheusServlet`** sink exposing `/metrics/prometheus` on the Spark UI (reachable on Databricks via the driver-proxy path); `spark.ui.prometheus.enabled=true` adds executor metrics | **Yes (pull)**, but partial coverage and awkward for ephemeral jobs |
| Billing / job / query history / lineage analytics | **System Tables** (Unity Catalog) — SQL-queryable operational data | Via SQL, not a metrics TSDB |

**So where does the blog's approach fit?** It targets the one gap with no
turnkey native answer: **full-fidelity Spark/JVM metrics from ephemeral job
clusters, in your own Prometheus/Grafana**. Two ways to fill it:

- **Native pull (`PrometheusServlet`)** — no extra jar. Add to
  `metrics.properties`:
  `*.sink.prometheusServlet.class=org.apache.spark.metrics.sink.PrometheusServlet`
  and scrape `/driver-proxy-api/o/0/<cluster_id>/<spark_ui_port>/metrics/prometheus/`.
  Simpler, but exposes a *subset* of metrics, needs a per-cluster scrape URL
  (the cluster id changes on each run), and the servlet doesn't follow
  Prometheus naming conventions.
- **OSS push (this POC, banzaicloud sink + Pushgateway)** — extra jar + init
  script, but **richer metrics** and it works cleanly for short-lived jobs
  because the job pushes on its way out instead of waiting to be scraped.

Reference docs:
- Compute Metrics UI: https://docs.databricks.com/aws/en/compute/cluster-metrics
- Serving-endpoint metrics export: https://docs.databricks.com/aws/en/machine-learning/model-serving/metrics-export-serving-endpoint
- Spark 3.0 native Prometheus: https://www.databricks.com/session_na20/native-support-of-prometheus-monitoring-in-apache-spark-3-0

---

## 3. Prerequisites

- A Databricks workspace + a **Personal Access Token** (or CLI profile).
- **Network reachability**: the Databricks cluster subnet must be able to reach
  the monitoring host on **:9091**. In a real workspace use **VNet/VPC
  injection** or VNet peering. A laptop running `docker compose` is *not*
  reachable from the cluster as `localhost` — use a small VM in (or peered to)
  the workspace network, or a tunnel.
- `docker` + `docker compose` on the monitoring host.
- `terraform >= 1.8` (only if using the Terraform path) and the Spark-3.5/Scala-2.12
  `spark_metrics.jar` placed in `databricks/lib/` (see `databricks/lib/README.md`).

---

## 4. Run it

> **Provisioning everything on Azure from scratch?** Use **`terraform/`**
> instead of this section — it builds the VNet, subnets, NAT gateway,
> VNet-injected workspace, and a VM that auto-starts this stack, then
> configures the cluster. See **`terraform/README.md`**. The steps below are
> the manual path / for when you already have a workspace and a monitoring host.

### Part A — stand up the monitoring stack

```bash
cd docker
docker compose up -d
docker compose ps          # all three should be "running"
```

Verify:
- Prometheus targets — http://<host>:9090/targets → `pushgateway` is **UP**
- Grafana — http://<host>:3000  (admin / admin) → dashboard **Databricks /
  Spark – Overview** is pre-loaded under the *Databricks* folder
- Pushgateway — http://<host>:9091  (empty until a job pushes)

### Part B — configure Databricks

**Option 1: Terraform — existing workspace, PAT auth** (for the full Azure
build incl. the workspace itself, use `terraform/` instead)

```bash
cd databricks
cp .env.example .env          # fill in host/token + pushgateway host:port
source .env
# put the jar in place (see lib/README.md):
#   cp /path/to/spark-metrics-assembly-3.5-1.3.0.jar lib/spark_metrics.jar
terraform init
terraform apply
```

This uploads the jar + init script to Workspace Files and creates the
**"DBX Observability POC"** single-node cluster with the right
`spark_env_vars` and init script attached.

**Option 2: Manual (UI), no Terraform**

1. **Workspace → Users → you** → upload `init-prometheus.sh` and your
   `spark_metrics.jar` (note their `/Workspace/...` paths).
2. **Compute → Create cluster** (or edit a job cluster):
   - **Advanced → Init Scripts**: add `Workspace` → path to `init-prometheus.sh`.
   - **Advanced → Spark → Environment variables**:
     ```
     METRICS_JAR_PATH=/Workspace/Users/<you>/.../spark_metrics.jar
     PROMETHEUS_HOST=<host>:9091
     PROMETHEUS_JOB_NAME=dbx-poc-interactive
     ```
3. Start the cluster.

### Part C — generate load & confirm the loop

Run any Spark workload on the cluster (e.g. a Pi-estimation notebook). Within
~10s:

- **Pushgateway** (http://<host>:9091) lists pushed groups.
- The Grafana dashboard's **Pipeline health** row goes green ("scrape UP",
  "distinct Spark series received" > 0), then JVM/Spark panels populate.

---

## 5. Discover your exact metric names

Metric names emitted by the sink depend on the sink version, the collectors
enabled, and the runtime. **The Pipeline-health panels are version-robust; the
JVM/Spark panels assume common names and may need adjusting.** To see what's
actually there:

1. Grafana → **Explore** → Prometheus datasource → **Metrics browser**, or
2. Prometheus → http://<host>:9090/graph → type a prefix and autocomplete.

Useful starting matchers:

| Looking for | Try |
|---|---|
| Everything from this stack | `{job_name=~".+"}` |
| JVM heap | `{__name__=~"jvm_.*heap.*"}` |
| GC | `{__name__=~"jvm_.*(MarkSweep|Scavenge|G1).*"}` |
| Scheduler | `{__name__=~"DAGScheduler_.*"}` |
| Executors | `{__name__=~"executor_.*"}` |
| Block manager | `{__name__=~"BlockManager_.*"}` |

Then update the corresponding panel's PromQL to match.

---

## 6. PromQL starter set

```promql
# Is anything arriving?
up{job="pushgateway"}
count({job_name=~".+"})

# Freshness: seconds since each group last pushed (stale groups keep climbing)
time() - push_time_seconds

# JVM heap used per instance
jvm_heap_used{job_name="dbx-poc-interactive"}

# Heap utilization %
100 * jvm_heap_used / jvm_heap_max

# GC rate (collections/sec), collector-agnostic
sum by (instance) (rate({__name__=~"jvm_.*(MarkSweep|Scavenge|G1).*count"}[1m]))
```

---

## 7. Known limitations & production hardening

This is a **POC**. Before relying on it:

- **Pushgateway is not designed for per-instance metrics.** The Prometheus
  project explicitly scopes Pushgateway to *service-level batch jobs*, not
  fleets of executors. It also **never expires** pushed series, so finished
  jobs leave **stale metrics** behind. Mitigate by wiping periodically
  (`curl -X PUT http://<host>:9091/api/v1/admin/wipe`, enabled here via
  `--web.enable-admin-api`) or by grouping pushes so they can be deleted. For
  large/long-running fleets, prefer the native `PrometheusServlet` pull path or
  a remote-write/OTel collector instead.
- **No persistence/HA.** Single-container Prometheus + Grafana with local
  volumes. For real use: managed Prometheus (e.g. Amazon Managed Service for
  Prometheus / Grafana Cloud), remote-write, retention/HA, and backups.
- **No security.** Everything is HTTP and unauthenticated. Add TLS, auth on
  Pushgateway/Prometheus/Grafana, and lock down :9091 to the cluster subnet
  only. Rotate the Grafana admin password and the Databricks PAT.
- **Single-node demo cluster.** `main.tf` builds a single-node cluster for
  clarity; for job metrics, attach the same init script + env vars to your
  real (multi-worker, possibly autoscaling) job clusters.
- **Cardinality.** JVM + Dropwizard + per-executor labels can produce a lot of
  series. Use the sink's `metrics-filter-regex` / `metrics-name-*` options to
  trim before they hit Prometheus.

### What I'd revisit as it grows
ephemeral push (Pushgateway) → for steady fleets, move to native pull or an
OpenTelemetry/remote-write collector writing to a managed, HA Prometheus, with
recording rules + Alertmanager for SLO alerting, and dashboards version-
controlled rather than hand-edited.

---

## 8. References

- Blog: https://community.databricks.com/t5/technical-blog/databricks-observability-using-grafana-and-prometheus/ba-p/96849
- Demo repo: https://github.com/rayalex/spark-databricks-observability
- Sink (Spark 3.x fork): https://github.com/rayalex/spark-metrics  ·  upstream: https://github.com/banzaicloud/spark-metrics
- Pushgateway: https://github.com/prometheus/pushgateway
- Spark monitoring: https://spark.apache.org/docs/latest/monitoring.html
