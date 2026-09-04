locals {
    resource_prefix = "${var.name_prefix}-${var.environment}"

    az = var.regions[var.region]["aws"].zone
}