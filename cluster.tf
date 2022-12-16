locals {
  subnets = [
    azurerm_subnet.cluster.id
  ]
  kubernetes_cluster_orchestrator_version                   = var.kubernetes_cluster_orchestrator_version == null ? data.azurerm_kubernetes_service_versions.main.latest_version : var.kubernetes_cluster_orchestrator_version
  kubernetes_cluster_default_node_pool_orchestrator_version = var.kubernetes_cluster_default_node_pool_orchestrator_version == null ? local.kubernetes_cluster_orchestrator_version : var.kubernetes_cluster_default_node_pool_orchestrator_version
  kubernetes_cluster_node_pool_orchestrator_version         = { for k, v in var.kubernetes_cluster_node_pools : k => v.orchestrator_version == null ? local.kubernetes_cluster_orchestrator_version : v.orchestrator_version }
}

resource "azurerm_user_assigned_identity" "cluster" {
  name                = "id-${local.resource_suffix}-aks"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
}

resource "azurerm_user_assigned_identity" "kubelet" {
  name                = "id-${local.resource_suffix}-kubelet"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
}

resource "azurerm_role_assignment" "cluster_network_contributor" {
  role_definition_name             = "Network Contributor"
  scope                            = azurerm_subnet.cluster.id
  principal_id                     = azurerm_user_assigned_identity.cluster.principal_id
  skip_service_principal_aad_check = true
}

resource "azurerm_role_assignment" "cluster_managed_identity_operator_kubelet" {
  role_definition_name             = "Managed Identity Operator"
  scope                            = azurerm_user_assigned_identity.kubelet.id
  principal_id                     = azurerm_user_assigned_identity.cluster.principal_id
  skip_service_principal_aad_check = true
}

resource "azurerm_role_assignment" "kubelet_registry_pull" {
  role_definition_name             = "AcrPull"
  scope                            = azurerm_container_registry.main.id
  principal_id                     = azurerm_user_assigned_identity.kubelet.principal_id
  skip_service_principal_aad_check = true
}

resource "azurerm_kubernetes_cluster" "main" {
  name                              = "aks-${local.global_resource_suffix}"
  location                          = azurerm_resource_group.main.location
  resource_group_name               = azurerm_resource_group.main.name
  dns_prefix                        = local.global_resource_suffix
  automatic_channel_upgrade         = var.kubernetes_cluster_automatic_channel_upgrade
  role_based_access_control_enabled = true
  azure_policy_enabled              = var.kubernetes_cluster_azure_policy_enabled
  open_service_mesh_enabled         = var.kubernetes_cluster_open_service_mesh_enabled
  kubernetes_version                = local.kubernetes_cluster_orchestrator_version
  local_account_disabled            = true
  oidc_issuer_enabled               = var.kubernetes_cluster_oidc_issuer_enabled
  node_resource_group               = "rg-${local.resource_suffix}-aks"
  sku_tier                          = var.kubernetes_cluster_sku_tier
  workload_identity_enabled         = var.kubernetes_cluster_oidc_issuer_enabled && var.kubernetes_cluster_workload_identity_enabled
  image_cleaner_enabled             = var.kubernetes_cluster_image_cleaner_enabled
  image_cleaner_interval_hours      = var.kubernetes_cluster_image_cleaner_enabled ? var.kubernetes_cluster_image_cleaner_interval_hours : null

  azure_active_directory_role_based_access_control {
    managed            = true
    azure_rbac_enabled = true
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.cluster.id]
  }

  default_node_pool {
    name                         = "system"
    vm_size                      = var.kubernetes_cluster_default_node_pool_vm_size
    enable_auto_scaling          = true
    min_count                    = var.kubernetes_cluster_default_node_pool_min_count
    max_count                    = var.kubernetes_cluster_default_node_pool_max_count
    max_pods                     = var.kubernetes_cluster_default_node_pool_max_pods
    os_disk_size_gb              = var.kubernetes_cluster_default_node_pool_os_disk_size_gb
    os_disk_type                 = var.kubernetes_cluster_default_node_pool_os_disk_type
    os_sku                       = var.kubernetes_cluster_default_node_pool_os_sku
    orchestrator_version         = local.kubernetes_cluster_default_node_pool_orchestrator_version
    only_critical_addons_enabled = true
    vnet_subnet_id               = azurerm_subnet.cluster.id
    zones                        = var.kubernetes_cluster_default_node_pool_zones == null ? var.zones : var.kubernetes_cluster_default_node_pool_zones

    upgrade_settings {
      max_surge = var.kubernetes_cluster_default_node_pool_max_surge
    }
  }

  oms_agent {
    log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  }

  network_profile {
    network_plugin      = var.kubernetes_cluster_overlay_network_plugin_mode_enabled ? "azure" : var.kubernetes_cluster_network_plugin
    network_policy      = var.kubernetes_cluster_cilium_data_plane_enabled ? null : var.kubernetes_cluster_network_policy
    dns_service_ip      = cidrhost(var.kubernetes_cluster_service_cidr, 10)
    docker_bridge_cidr  = var.kubernetes_cluster_docker_bridge_cidr
    service_cidr        = var.kubernetes_cluster_service_cidr
    load_balancer_sku   = "standard"
    outbound_type       = "userAssignedNATGateway"
    ebpf_data_plane     = var.kubernetes_cluster_cilium_data_plane_enabled ? "cilium" : null
    network_plugin_mode = var.kubernetes_cluster_overlay_network_plugin_mode_enabled ? "Overlay" : null
    pod_cidr            = var.kubernetes_cluster_network_plugin == "azure" && !var.kubernetes_cluster_overlay_network_plugin_mode_enabled ? null : var.kubernetes_cluster_pod_cidr
  }

  storage_profile {
    blob_driver_enabled         = var.kubernetes_cluster_blob_driver_enabled
    disk_driver_enabled         = var.kubernetes_cluster_disk_driver_enabled
    disk_driver_version         = "v${var.kubernetes_cluster_disk_driver_version}"
    file_driver_enabled         = var.kubernetes_cluster_file_driver_enabled
    snapshot_controller_enabled = var.kubernetes_cluster_snapshot_controller_enabled
  }

  linux_profile {
    admin_username = var.kubernetes_cluster_admin_username
    ssh_key {
      key_data = file(var.kubernetes_cluster_ssh_key_path)
    }
  }

  kubelet_identity {
    client_id                 = azurerm_user_assigned_identity.kubelet.client_id
    object_id                 = azurerm_user_assigned_identity.kubelet.principal_id
    user_assigned_identity_id = azurerm_user_assigned_identity.kubelet.id
  }

  dynamic "key_vault_secrets_provider" {
    for_each = var.kubernetes_cluster_key_vault_secrets_provider_enabled ? [{}] : []
    content {
      secret_rotation_enabled  = true
      secret_rotation_interval = "1m"
    }
  }

  dynamic "microsoft_defender" {
    for_each = var.kubernetes_cluster_microsoft_defender_enabled ? [{}] : []
    content {
      log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
    }
  }

  depends_on = [
    azurerm_subnet_nat_gateway_association.cluster,
    azurerm_role_assignment.cluster_network_contributor,
    azurerm_role_assignment.cluster_managed_identity_operator_kubelet,
  ]
}

resource "azurerm_kubernetes_cluster_node_pool" "main" {
  for_each              = var.kubernetes_cluster_node_pools
  name                  = each.key
  kubernetes_cluster_id = azurerm_kubernetes_cluster.main.id
  vm_size               = each.value.vm_size
  enable_auto_scaling   = true
  min_count             = each.value.min_count
  max_count             = each.value.max_count
  max_pods              = each.value.max_pods
  os_disk_size_gb       = each.value.os_disk_size_gb
  os_disk_type          = each.value.os_disk_type
  os_sku                = each.value.os_sku
  os_type               = each.value.os_type
  orchestrator_version  = local.kubernetes_cluster_node_pool_orchestrator_version[each.key]
  vnet_subnet_id        = azurerm_subnet.cluster.id
  zones                 = each.value.zones == null ? var.zones : each.value.zones
  node_labels           = each.value.node_labels
  node_taints           = each.value.node_taints

  upgrade_settings {
    max_surge = each.value.max_surge
  }
}

resource "local_file" "kube_config" {
  filename = ".kube/config"
  content  = azurerm_kubernetes_cluster.main.kube_config_raw

  provisioner "local-exec" {
    command = "kubelogin convert-kubeconfig -l spn --client-id ${var.client_id} --client-secret ${var.client_secret}"
    environment = {
      KUBECONFIG = ".kube/config"
    }
  }
}

resource "azurerm_role_assignment" "aks_cluster_administrator" {
  for_each             = toset(var.kubernetes_service_cluster_administrators)
  role_definition_name = "Azure Kubernetes Service Cluster Admin Role"
  principal_id         = each.value
  scope                = azurerm_kubernetes_cluster.main.id
}

resource "azurerm_role_assignment" "kubernetes_service_cluster_user" {
  for_each             = toset(var.kubernetes_service_cluster_users)
  role_definition_name = "Azure Kubernetes Service Cluster User Role"
  principal_id         = each.value
  scope                = azurerm_kubernetes_cluster.main.id
}

resource "azurerm_role_assignment" "kubernetes_service_rbac_administrator" {
  for_each             = toset(var.kubernetes_service_rbac_administrators)
  role_definition_name = "Azure Kubernetes Service RBAC Admin"
  principal_id         = each.value
  scope                = azurerm_kubernetes_cluster.main.id
}

resource "azurerm_role_assignment" "kubernetes_service_rbac_cluster_administrator" {
  for_each             = toset(concat([data.azurerm_client_config.main.object_id], var.kubernetes_service_rbac_cluster_administrators))
  role_definition_name = "Azure Kubernetes Service RBAC Cluster Admin"
  principal_id         = each.value
  scope                = azurerm_kubernetes_cluster.main.id
}

resource "azurerm_role_assignment" "kubernetes_service_rbac_reader" {
  for_each             = toset(var.kubernetes_service_rbac_readers)
  role_definition_name = "Azure Kubernetes Service RBAC Reader"
  principal_id         = each.value
  scope                = azurerm_kubernetes_cluster.main.id
}

resource "azurerm_role_assignment" "kubernetes_service_rbac_writer" {
  for_each             = toset(var.kubernetes_service_rbac_writers)
  role_definition_name = "Azure Kubernetes Service RBAC Writer"
  principal_id         = each.value
  scope                = azurerm_kubernetes_cluster.main.id
}
