locals {
  # Every metric the dashboard shows and alerting watches, in one place.
  # CloudWatch reports sums per period, so per-second thresholds are scaled
  # by the 60-second period here and nowhere else. The health check has no
  # threshold to cross: any failed check, or no data at all, means down.
  metrics = {
    cpu = {
      title      = "CPU utilization (%)"
      namespace  = "AWS/EC2"
      name       = "CPUUtilization"
      stat       = "Average"
      dimension  = "InstanceId"
      threshold  = var.thresholds.cpu_utilization * 100
      comparison = "GreaterThanThreshold"
      missing    = "notBreaching"
    }
    memory = {
      title      = "Memory used (bytes)"
      namespace  = "CWAgent"
      name       = "mem_used"
      stat       = "Average"
      dimension  = "InstanceId"
      threshold  = var.thresholds.memory_used_gb * 1073741824
      comparison = "GreaterThanThreshold"
      missing    = "notBreaching"
    }
    disk_write = {
      title      = "Disk write operations per minute"
      namespace  = "AWS/EBS"
      name       = "VolumeWriteOps"
      stat       = "Sum"
      dimension  = "VolumeId"
      threshold  = var.thresholds.disk_write_ops_per_second * 60
      comparison = "GreaterThanThreshold"
      missing    = "notBreaching"
    }
    network_in = {
      title      = "Network bytes received per minute"
      namespace  = "AWS/EC2"
      name       = "NetworkIn"
      stat       = "Sum"
      dimension  = "InstanceId"
      threshold  = var.thresholds.network_received_mbit_per_second * 125000 * 60
      comparison = "GreaterThanThreshold"
      missing    = "notBreaching"
    }
    health = {
      title      = "Status checks failed"
      namespace  = "AWS/EC2"
      name       = "StatusCheckFailed"
      stat       = "Maximum"
      dimension  = "InstanceId"
      threshold  = 1
      comparison = "GreaterThanOrEqualToThreshold"
      missing    = "breaching"
    }
  }
}

# Counterpart of roles/monitoring.metricWriter. Metrics have no ARN, so the
# namespace condition is what keeps this narrow.
resource "aws_iam_role_policy" "metric_writer" {
  for_each = var.identities

  name = "${var.resource_prefix}-${each.key}-metric-writer"
  role = each.value

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = ["cloudwatch:PutMetricData"]
      Resource  = "*"
      Condition = { StringEquals = { "cloudwatch:namespace" = "CWAgent" } }
    }]
  })
}

resource "aws_cloudwatch_dashboard" "hosts" {
  dashboard_name = "${var.resource_prefix}-hosts"

  dashboard_body = jsonencode({
    widgets = [
      for name, metric in local.metrics : {
        type   = "metric"
        x      = index(keys(local.metrics), name) % 2 * 12
        y      = floor(index(keys(local.metrics), name) / 2) * 6
        width  = 12
        height = 6
        properties = {
          title  = metric.title
          region = var.region
          view   = "timeSeries"
          stat   = metric.stat
          period = 60
          metrics = [
            for instance, ids in var.instances :
            [metric.namespace, metric.name, metric.dimension, metric.dimension == "VolumeId" ? ids.volume_id : ids.id, { label = instance }]
          ]
          annotations = { horizontal = [{ value = metric.threshold, label = "alert" }] }
        }
      }
    ]
  })
}
