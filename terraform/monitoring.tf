################################################################################
# CloudWatch Dashboard
################################################################################

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${local.cluster_name}-dashboard"

  dashboard_body = jsonencode({
    startY = 0
    periodOverride = "auto"
    widgets = [
      {
        type = "metric"
        x    = 0
        y    = 0
        width = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/ContainerInsights", "pod_cpu_utilization", "ClusterName", local.cluster_name, { stat = "Average", label = "${local.name_prefix}-backend" }]
          ]
          period = 300
          stat   = "Average"
          region = var.aws_region
          title  = "Pod CPU Utilization (%)"
          view   = "timeSeries"
          stacked = false
          yAxis = {
            left = {
              min = 0
              max = 100
            }
          }
        }
      },
      {
        type = "metric"
        x    = 12
        y    = 0
        width = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/ContainerInsights", "pod_memory_utilization", "ClusterName", local.cluster_name, { stat = "Average", label = "${local.name_prefix}-backend" }]
          ]
          period = 300
          stat   = "Average"
          region = var.aws_region
          title  = "Pod Memory Utilization (%)"
          view   = "timeSeries"
          stacked = false
          yAxis = {
            left = {
              min = 0
              max = 100
            }
          }
        }
      },
      {
        type = "metric"
        x    = 0
        y    = 6
        width = 8
        height = 6
        properties = {
          metrics = [
            ["AWS/ContainerInsights", "node_count", "ClusterName", local.cluster_name, { stat = "Average" }]
          ]
          period = 300
          stat   = "Average"
          region = var.aws_region
          title  = "Active Nodes"
          view   = "singleValue"
        }
      },
      {
        type = "metric"
        x    = 8
        y    = 6
        width = 8
        height = 6
        properties = {
          metrics = [
            ["AWS/ContainerInsights", "node_cpu_utilization", "ClusterName", local.cluster_name, { stat = "Average" }]
          ]
          period = 300
          stat   = "Average"
          region = var.aws_region
          title  = "Node CPU Utilization (%)"
          view   = "timeSeries"
          yAxis = {
            left = {
              min = 0
              max = 100
            }
          }
        }
      },
      {
        type = "metric"
        x    = 16
        y    = 6
        width = 8
        height = 6
        properties = {
          metrics = [
            ["AWS/ContainerInsights", "node_memory_utilization", "ClusterName", local.cluster_name, { stat = "Average" }]
          ]
          period = 300
          stat   = "Average"
          region = var.aws_region
          title  = "Node Memory Utilization (%)"
          view   = "timeSeries"
          yAxis = {
            left = {
              min = 0
              max = 100
            }
          }
        }
      },
      {
        type = "log"
        x    = 0
        y    = 12
        width = 24
        height = 6
        properties = {
          query = "SOURCE '/aws/eks/${local.cluster_name}/cluster' | fields @timestamp, @message, @logStream\n| sort @timestamp desc\n| limit 50"
          region = var.aws_region
          title  = "Control Plane Logs"
          view   = "table"
        }
      },
    ]
  })
}
