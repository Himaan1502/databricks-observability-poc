# Place the spark-metrics assembly jar here

Terraform expects this file:

    lib/spark_metrics.jar

It is the **banzaicloud spark-metrics** sink, built for Spark 3.5 (Scala 2.12).
It contains the class the init script wires in:
`org.apache.spark.banzaicloud.metrics.sink.PrometheusSink`.

Get it one of two ways:

**Option 1 – prebuilt (fastest).** Download from the upstream demo repo and rename:

    # from https://github.com/rayalex/spark-databricks-observability/tree/main/lib
    #   spark-metrics-assembly-3.5-1.3.0.jar
    cp spark-metrics-assembly-3.5-1.3.0.jar lib/spark_metrics.jar

**Option 2 – build it yourself** from https://github.com/rayalex/spark-metrics

    git clone https://github.com/rayalex/spark-metrics
    cd spark-metrics && sbt assembly
    # copy target/scala-2.12/spark-metrics-assembly-*.jar -> lib/spark_metrics.jar

Match the jar's Scala version (2.12 vs 2.13) to your Databricks Runtime.
DBR 13.x–15.x LTS ships Spark 3.4/3.5 on Scala 2.12, so the 3.5 / 2.12 jar fits.
