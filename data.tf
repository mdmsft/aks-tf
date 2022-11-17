data "azurerm_client_config" "main" {}

data "azuread_client_config" "main" {}

data "azurerm_kubernetes_service_versions" "main" {
  location        = var.location
  include_preview = var.kubernetes_service_versions_include_preview
}
