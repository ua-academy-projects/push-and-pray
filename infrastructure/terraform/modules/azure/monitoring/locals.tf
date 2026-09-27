locals {
  duration_windows = {
    60   = "PT1M"
    300  = "PT5M"
    600  = "PT10M"
    900  = "PT15M"
    1800 = "PT30M"
    3600 = "PT1H"
  }

  cpu_window  = lookup(local.duration_windows, var.settings.cpu.duration_seconds, "PT5M")
  disk_window = lookup(local.duration_windows, var.settings.disk.duration_seconds, "PT10M")
}
