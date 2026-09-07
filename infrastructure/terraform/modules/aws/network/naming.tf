locals {
  location_suffixes = {
    for location in keys(local.locations) :
    location => location == var.config.default_location ? "" : "-${location}"
  }

  labels          = merge(var.config.common_labels, { environment = var.config.environment })
  resource_prefix = "${var.config.name_prefix}-${var.config.environment}"
}
