locals {
  resource_prefix  = "${var.config.name_prefix}-${var.config.environment}"
  application_host = var.config.k3s.application.hostname
  application_ns   = var.config.k3s.application.namespace
  cluster_id       = lower(var.cluster.id)
  action_group_ids = var.action_group_id == null ? [] : [var.action_group_id]

  tags = merge(
    {
      application = var.config.name_prefix
      environment = var.config.environment
      managed_by  = "terraform"
    },
    var.config.common_labels,
  )

  node_metric_alerts = {
    cpu = {
      name        = "${local.resource_prefix}-aks-high-node-cpu"
      description = "An AKS worker node has used more than 85 percent CPU for 10 minutes."
      metric      = "node_cpu_usage_percentage"
      threshold   = 85
      aggregation = "Average"
      dimensions = [{
        name   = "node"
        values = ["*"]
      }]
    }
    memory = {
      name        = "${local.resource_prefix}-aks-high-node-memory"
      description = "An AKS worker node has used more than 85 percent working-set memory for 10 minutes."
      metric      = "node_memory_working_set_percentage"
      threshold   = 85
      aggregation = "Average"
      dimensions = [{
        name   = "node"
        values = ["*"]
      }]
    }
    disk = {
      name        = "${local.resource_prefix}-aks-high-node-disk"
      description = "An AKS worker node root filesystem has averaged more than 85 percent full for 15 minutes."
      metric      = "node_disk_usage_percentage"
      threshold   = 85
      aggregation = "Average"
      dimensions = [
        {
          name   = "node"
          values = ["*"]
        },
        {
          name   = "device"
          values = ["/dev/root"]
        },
      ]
    }
  }

  log_alerts = {
    node_not_ready = {
      name        = "${local.resource_prefix}-aks-node-not-ready"
      description = "One or more AKS worker nodes have not reported Ready during the last ten minutes."
      severity    = 1
      query       = <<-KQL
        KubeNodeInventory
        | where _ResourceId =~ "${local.cluster_id}"
        | summarize arg_max(TimeGenerated, Status) by Computer
        | where Status !contains "Ready"
        | project TimeGenerated=now(), Computer
      KQL
    }
    application_pods = {
      name        = "${local.resource_prefix}-aks-unhealthy-application-pods"
      description = "An OilScope pod is Pending, Failed, or Unknown."
      severity    = 1
      query       = <<-KQL
        KubePodInventory
        | where _ResourceId =~ "${local.cluster_id}"
        | where Namespace == "${local.application_ns}"
        | summarize arg_max(TimeGenerated, PodStatus) by PodUid, Name
        | where PodStatus in ("Pending", "Failed", "Unknown")
        | project TimeGenerated=now(), Name, PodStatus
      KQL
    }
    container_restarts = {
      name        = "${local.resource_prefix}-aks-container-restarts"
      description = "An OilScope container restarted at least three times within ten minutes."
      severity    = 1
      query       = <<-KQL
        KubePodInventory
        | where _ResourceId =~ "${local.cluster_id}"
        | where Namespace == "${local.application_ns}"
        | summarize FirstRestartCount=min(ContainerRestartCount), LastRestartCount=max(ContainerRestartCount) by PodUid, ContainerName
        | extend RestartIncrease=LastRestartCount-FirstRestartCount
        | where RestartIncrease >= 3
        | project TimeGenerated=now(), ContainerName, RestartIncrease
      KQL
    }
  }

  workbook_queries = [
    {
      title         = "Nodes - CPU utilization"
      query         = <<-KQL
        let capacity = Perf
          | where _ResourceId =~ "${local.cluster_id}"
          | where ObjectName == "K8SNode" and CounterName == "cpuCapacityNanoCores"
          | summarize Capacity=max(CounterValue) by Computer, bin(TimeGenerated, 5m);
        let usage = Perf
          | where _ResourceId =~ "${local.cluster_id}"
          | where ObjectName == "K8SNode" and CounterName == "cpuUsageNanoCores"
          | summarize Usage=avg(CounterValue) by Computer, bin(TimeGenerated, 5m);
        capacity
        | join kind=inner usage on Computer, TimeGenerated
        | extend CPUPercent=100.0 * Usage / Capacity
        | project TimeGenerated, Computer, CPUPercent
        | render timechart
      KQL
      visualization = "timechart"
    },
    {
      title         = "Nodes - Memory utilization"
      query         = <<-KQL
        let capacity = Perf
          | where _ResourceId =~ "${local.cluster_id}"
          | where ObjectName == "K8SNode" and CounterName == "memoryCapacityBytes"
          | summarize Capacity=max(CounterValue) by Computer, bin(TimeGenerated, 5m);
        let usage = Perf
          | where _ResourceId =~ "${local.cluster_id}"
          | where ObjectName == "K8SNode" and CounterName == "memoryRssBytes"
          | summarize Usage=avg(CounterValue) by Computer, bin(TimeGenerated, 5m);
        capacity
        | join kind=inner usage on Computer, TimeGenerated
        | extend MemoryPercent=100.0 * Usage / Capacity
        | project TimeGenerated, Computer, MemoryPercent
        | render timechart
      KQL
      visualization = "timechart"
    },
    {
      title         = "Nodes - Root filesystem utilization"
      query         = <<-KQL
        InsightsMetrics
        | where _ResourceId =~ "${local.cluster_id}"
        | where Origin == "container.azm.ms/telegraf" and Namespace == "container.azm.ms/disk"
        | where Name == "used_percent"
        | extend Disk=todynamic(Tags)
        | extend Computer=tostring(Disk.hostName), Device=tostring(Disk.device), Path=tostring(Disk.path)
        | where Device == "/dev/root" or Path == "/"
        | summarize DiskUsedPercent=max(Val) by bin(TimeGenerated, 5m), Computer
        | render timechart
      KQL
      visualization = "timechart"
    },
    {
      title         = "Pods - Count by phase"
      query         = <<-KQL
        KubePodInventory
        | where _ResourceId =~ "${local.cluster_id}"
        | summarize PodStatus=any(PodStatus) by bin(TimeGenerated, 5m), PodUid
        | summarize Pods=count() by TimeGenerated, PodStatus
        | render timechart
      KQL
      visualization = "timechart"
    },
    {
      title         = "Pods - Count by namespace"
      query         = <<-KQL
        KubePodInventory
        | where _ResourceId =~ "${local.cluster_id}"
        | summarize Pods=dcount(PodUid) by bin(TimeGenerated, 5m), Namespace
        | render timechart
      KQL
      visualization = "timechart"
    },
    {
      title         = "OilScope containers - CPU usage"
      query         = <<-KQL
        let inventory = KubePodInventory
          | where _ResourceId =~ "${local.cluster_id}" and Namespace == "${local.application_ns}"
          | extend PerfInstance=strcat(ClusterId, "/", ContainerName)
          | summarize arg_max(TimeGenerated, Name, ControllerName) by Computer, PerfInstance;
        Perf
        | where _ResourceId =~ "${local.cluster_id}"
        | where ObjectName == "K8SContainer" and CounterName == "cpuUsageNanoCores"
        | join kind=inner inventory on $left.Computer == $right.Computer, $left.InstanceName == $right.PerfInstance
        | summarize CPUCores=avg(CounterValue) / 1000000000.0 by bin(TimeGenerated, 5m), ControllerName
        | render timechart
      KQL
      visualization = "timechart"
    },
    {
      title         = "OilScope containers - Memory used"
      query         = <<-KQL
        let inventory = KubePodInventory
          | where _ResourceId =~ "${local.cluster_id}" and Namespace == "${local.application_ns}"
          | extend PerfInstance=strcat(ClusterId, "/", ContainerName)
          | summarize arg_max(TimeGenerated, Name, ControllerName) by Computer, PerfInstance;
        Perf
        | where _ResourceId =~ "${local.cluster_id}"
        | where ObjectName == "K8SContainer" and CounterName == "memoryRssBytes"
        | join kind=inner inventory on $left.Computer == $right.Computer, $left.InstanceName == $right.PerfInstance
        | summarize MemoryBytes=avg(CounterValue) by bin(TimeGenerated, 5m), ControllerName
        | render timechart
      KQL
      visualization = "timechart"
    },
    {
      title         = "OilScope containers - Restarts"
      query         = <<-KQL
        KubePodInventory
        | where _ResourceId =~ "${local.cluster_id}" and Namespace == "${local.application_ns}"
        | extend Container=tostring(split(ContainerName, "/")[-1])
        | summarize Restarts=max(ContainerRestartCount) by bin(TimeGenerated, 5m), Container
        | render timechart
      KQL
      visualization = "timechart"
    },
    {
      title         = "OilScope pod state"
      query         = <<-KQL
        KubePodInventory
        | where _ResourceId =~ "${local.cluster_id}" and Namespace == "${local.application_ns}"
        | summarize arg_max(TimeGenerated, PodStatus, ContainerStatus, ContainerStatusReason) by PodUid, Name
        | project Name, PodStatus, ContainerStatus, ContainerStatusReason, TimeGenerated
        | order by Name asc
      KQL
      visualization = "table"
    },
    {
      title         = "Recent Kubernetes warnings"
      query         = <<-KQL
        KubeEvents
        | where _ResourceId =~ "${local.cluster_id}"
        | where KubeEventType == "Warning"
        | project TimeGenerated, Namespace, Name, Reason, Message
        | order by TimeGenerated desc
        | take 100
      KQL
      visualization = "table"
    },
    {
      title         = "HTTPS availability"
      query         = <<-KQL
        AppAvailabilityResults
        | where Name == "${local.resource_prefix}-aks-https-availability"
        | summarize Availability=100.0 * countif(Success) / count() by bin(TimeGenerated, 15m)
        | render timechart
      KQL
      visualization = "timechart"
    },
  ]
}
