resource "aws_cloudwatch_metric_alarm" "cpu_high" {
    for_each = local.selected_vms

    alarm_name = "${local.resource_prefix}-${each.key}-cpu-high"
    namespace = "AWS/EC2"
    metric_name = "CPUUtilization"
    dimensions = {
        InstanceId = var.instance_ids[each.key]    
}

    statistic = "Average"
    period = 60
    evaluation_periods = 1
    comparison_operator = "GreaterThanThreshold"
    threshold = try(var.config.monitoring.cpu_threshold_percent, 80)
    
    alarm_actions = [aws_sns_topic.alerts[0].arn]
}

resource "aws_cloudwatch_metric_alarm" "instance_down" {
    for_each = local.selected_vms

    alarm_name = "${local.resource_prefix}-${each.key}-instance-down"
    namespace = "AWS/EC2"
    metric_name = "StatusCheckFailed"
    dimensions = {
        InstanceId = var.instance_ids[each.key]
    }

    statistic = "Maximum"
    period = 60
    evaluation_periods = 1
    comparison_operator = "GreaterThanThreshold"
    threshold = 0

    alarm_actions = [aws_sns_topic.alerts[0].arn]
}