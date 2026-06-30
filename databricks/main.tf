terraform {
  required_version = ">= 1.8.0"
  required_providers {
    databricks = {
      source  = "databricks/databricks"
      version = ">= 1.40"
    }
  }
}

# Auth via env vars (DATABRICKS_HOST + DATABRICKS_TOKEN) or a CLI profile.
# To use a profile instead, set:  profile = "my-profile"
provider "databricks" {}

data "databricks_current_user" "me" {}

data "databricks_spark_version" "lts" {
  long_term_support = true
}

data "databricks_node_type" "smallest" {
  local_disk = true
}

# --- Upload the sink jar to Workspace Files -------------------------------
# Drop spark_metrics.jar into ./lib first (see lib/README.md).
resource "databricks_workspace_file" "prometheus_jar" {
  source = "${path.module}/lib/spark_metrics.jar"
  path   = "${data.databricks_current_user.me.home}/dbx-obs/spark_metrics.jar"
}

# --- Upload the init script ------------------------------------------------
resource "databricks_workspace_file" "prometheus_init" {
  source = "${path.module}/init-prometheus.sh"
  path   = "${data.databricks_current_user.me.home}/dbx-obs/init-prometheus.sh"
}

# --- Demo single-node cluster, configured to push metrics ------------------
resource "databricks_cluster" "demo" {
  cluster_name            = "DBX Observability POC"
  spark_version           = data.databricks_spark_version.lts.id
  node_type_id            = data.databricks_node_type.smallest.id
  autotermination_minutes = 30
  num_workers             = 0

  init_scripts {
    workspace {
      destination = databricks_workspace_file.prometheus_init.path
    }
  }

  spark_conf = {
    "spark.master"                     = "local[*]"
    "spark.databricks.cluster.profile" = "singleNode"
  }

  # These env vars are consumed by init-prometheus.sh
  spark_env_vars = {
    "METRICS_JAR_PATH"    = databricks_workspace_file.prometheus_jar.workspace_path
    "PROMETHEUS_HOST"     = var.prometheus_pushgateway_host
    "PROMETHEUS_JOB_NAME" = "dbx-poc-interactive"
  }

  custom_tags = {
    "ResourceClass" = "SingleNode"
  }
}

output "cluster_id" {
  value = databricks_cluster.demo.id
}
