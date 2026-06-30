# Pull stage 1's outputs (workspace URL/ID, pushgateway endpoint) from the
# shared Azure state backend. Run stage 1 first so foundation.tfstate exists.
data "terraform_remote_state" "foundation" {
  backend = "azurerm"
  config = {
    resource_group_name  = var.state_resource_group_name
    storage_account_name = var.state_storage_account_name
    container_name       = var.state_container_name
    key                  = "foundation.tfstate"
    use_azuread_auth     = true
  }
}

# Authenticate to the workspace using your Azure CLI login (run `az login`).
# No PAT required – the provider exchanges your AAD token for the workspace.
provider "databricks" {
  host                        = data.terraform_remote_state.foundation.outputs.databricks_workspace_url
  azure_workspace_resource_id = data.terraform_remote_state.foundation.outputs.databricks_workspace_id
}

locals {
  pushgateway_host = var.prometheus_pushgateway_host != "" ? var.prometheus_pushgateway_host : data.terraform_remote_state.foundation.outputs.pushgateway_endpoint
}

data "databricks_current_user" "me" {}

data "databricks_spark_version" "lts" {
  long_term_support = true
}

data "databricks_node_type" "smallest" {
  local_disk = true
}

# --- Upload the sink jar (place it at databricks/lib/spark_metrics.jar) -----
resource "databricks_workspace_file" "jar" {
  source = "${path.module}/../../databricks/lib/spark_metrics.jar"
  path   = "${data.databricks_current_user.me.home}/dbx-obs/spark_metrics.jar"
}

# --- Upload the init script -------------------------------------------------
resource "databricks_workspace_file" "init" {
  source = "${path.module}/../../databricks/init-prometheus.sh"
  path   = "${data.databricks_current_user.me.home}/dbx-obs/init-prometheus.sh"
}

# --- Demo single-node cluster, pre-wired to push metrics --------------------
resource "databricks_cluster" "demo" {
  cluster_name            = "DBX Observability POC"
  spark_version           = data.databricks_spark_version.lts.id
  node_type_id            = data.databricks_node_type.smallest.id
  autotermination_minutes = 30
  num_workers             = 0

  init_scripts {
    workspace {
      destination = databricks_workspace_file.init.path
    }
  }

  spark_conf = {
    "spark.master"                     = "local[*]"
    "spark.databricks.cluster.profile" = "singleNode"
  }

  spark_env_vars = {
    "METRICS_JAR_PATH"    = databricks_workspace_file.jar.workspace_path
    "PROMETHEUS_HOST"     = local.pushgateway_host
    "PROMETHEUS_JOB_NAME" = var.job_name
  }

  custom_tags = {
    "ResourceClass" = "SingleNode"
  }
}
