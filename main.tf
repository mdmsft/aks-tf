resource "random_string" "project" {
  length  = 4
  numeric = false
  upper   = false
  special = false
}

resource "azurerm_resource_group" "main" {
  name     = "rg-${local.resource_suffix}"
  location = var.location
  tags     = var.tags

  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}
