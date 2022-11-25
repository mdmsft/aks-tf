locals {
  project                = var.project == null ? random_string.project.result : var.project
  environment            = terraform.workspace == "default" ? var.environment : terraform.workspace
  resource_suffix        = "${local.project}-${local.environment}-${var.region}"
  global_resource_suffix = "${local.project}-${local.environment}"
}
