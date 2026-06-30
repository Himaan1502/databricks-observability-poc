#!/bin/bash
# ---------------------------------------------------------------------------
# Cluster-scoped init script: wire Spark's metrics system into the
# banzaicloud PrometheusSink so every JVM (driver + executors) pushes metrics
# to a Prometheus Pushgateway.
#
# Runs once per node, BEFORE the Spark JVM starts, so metrics.properties is in
# place when the Spark context boots.
#
# Reads three cluster environment variables (set them on the cluster, see
# main.tf / cluster-setup, NOT hard-coded here so the same script is reusable):
#   METRICS_JAR_PATH    Workspace path of the spark-metrics assembly jar
#                       e.g. /Workspace/Users/me@co.com/dbx-obs/spark_metrics.jar
#   PROMETHEUS_HOST     host:port of the Pushgateway, e.g. 10.0.0.5:9091
#   PROMETHEUS_JOB_NAME logical job label, e.g. dbx-calculate-pi
# ---------------------------------------------------------------------------
set -euo pipefail

# 1) Put the sink jar on the Spark classpath
cp "${METRICS_JAR_PATH}" /databricks/jars/

# 2) JMX collector config (lets the sink also export JVM MBeans)
cat > /databricks/spark/conf/jmxCollector.yaml <<EOL
lowercaseOutputName: false
lowercaseOutputLabelNames: false
whitelistObjectNames: ["*:*"]
EOL

# 3) Spark metrics sink configuration
cat >> /databricks/spark/conf/metrics.properties <<EOL
# --- Prometheus push sink (banzaicloud) ---
*.sink.prometheus.class=org.apache.spark.banzaicloud.metrics.sink.PrometheusSink
*.sink.prometheus.pushgateway-address-protocol=http
*.sink.prometheus.pushgateway-address=${PROMETHEUS_HOST}
*.sink.prometheus.period=5
*.sink.prometheus.labels=job_name=${PROMETHEUS_JOB_NAME}

# Collectors: Dropwizard (Spark's own metrics) + JMX (JVM MBeans)
*.sink.prometheus.enable-dropwizard-collector=true
*.sink.prometheus.enable-jmx-collector=true
*.sink.prometheus.jmx-collector-config=/databricks/spark/conf/jmxCollector.yaml

# Use hostname (not app-id) as the 'instance' so each executor is distinct
*.sink.prometheus.enable-hostname-in-instance=true

# JVM metrics source
# *.sink.jmx.class=org.apache.spark.metrics.sink.JmxSink
# *.source.jvm.class=org.apache.spark.metrics.source.JvmSource
EOL

echo "[init-prometheus] sink configured -> ${PROMETHEUS_HOST} (job_name=${PROMETHEUS_JOB_NAME})"
