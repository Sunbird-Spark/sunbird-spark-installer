 terraform {
  required_providers {
    azurerm = {
      version = "~> 4.0"
      source  = "hashicorp/azurerm"
    }
  }
}

provider "azurerm" {
  subscription_id = var.subscription_id
  features {}
}
  locals {
      common_tags = {
        environment = "${var.environment}"
        BuildingBlock = "${var.building_block}"
      }
      environment_name = "${var.building_block}-${var.environment}"
  }

  resource "azurerm_kubernetes_cluster" "aks" {
    name                = "${local.environment_name}"
    location            = var.location
    resource_group_name = var.resource_group_name
    dns_prefix          = "${local.environment_name}"
    kubernetes_version  = var.aks_version

    #Uncomment the below line to create a private cluster
    # private_cluster_enabled = true
    oidc_issuer_enabled       = true
    workload_identity_enabled = true
    default_node_pool {
      name           = var.big_nodepool_name
      node_count     = var.big_node_count
      vm_size        = var.big_node_size
      vnet_subnet_id = var.vnet_subnet_id
      max_pods       = 250
    }

    network_profile {
      network_plugin      = var.network_plugin
      network_plugin_mode = "overlay"
      service_cidr        = var.service_cidr
      dns_service_ip      = var.dns_service_ip
    }

    # Use System-Assigned Managed Identity
    # No Azure AD permissions needed - only Contributor role on Resource Group
    # Identity auto-created with cluster, auto-deleted when cluster deleted
    identity {
      type = "SystemAssigned"
    }

    tags = merge(
        local.common_tags,
        var.additional_tags
        )
  }

  # Grant Network Contributor role to AKS System-Assigned Identity
  resource "azurerm_role_assignment" "aks_network_contributor" {
    principal_id         = azurerm_kubernetes_cluster.aks.identity[0].principal_id
    scope                = var.vnet_subnet_id
    role_definition_name = "Network Contributor"
    
    depends_on = [azurerm_kubernetes_cluster.aks]
  }

  # resource "azurerm_kubernetes_cluster_node_pool" "small_nodepool" {
  #   name                  = var.small_nodepool_name
  #   kubernetes_cluster_id = azurerm_kubernetes_cluster.aks.id
  #   vm_size               = var.small_node_size
  #   node_count            = var.small_node_count
  #   vnet_subnet_id        = var.vnet_subnet_id
  #   mode                  = "System"
  #   enable_auto_scaling   = true
  #   min_count             = 1
  #   max_count             = var.max_small_nodepool_nodes
  #   tags = merge(
  #       local.common_tags,
  #       var.additional_tags
  #       )
  #   depends_on = [ azurerm_kubernetes_cluster.aks ]
  # }
  resource "null_resource" "kubeconfig" {
    triggers = {
      cluster_id      = azurerm_kubernetes_cluster.aks.id
      cluster_version = azurerm_kubernetes_cluster.aks.kubernetes_version
    }

    provisioner "local-exec" {
      command = "az aks get-credentials --resource-group ${var.resource_group_name} --name ${azurerm_kubernetes_cluster.aks.name} --overwrite-existing"
    }

    depends_on = [azurerm_kubernetes_cluster.aks]
  }

  # Pre-create private LB in future if ever there is an instance of private ip
  # taken by node or some other service.
  # Better option is to use lookup in charts where private ingress ip is required.

  # resource "azurerm_lb" "private_lb" {
  #   name                = "private-ilb"
  #   resource_group_name = var.resource_group_name
  #   location            = var.location
  #   sku                 = "Standard"
  #   frontend_ip_configuration {
  #     name                          = "ilb-frontend-ip"
  #     subnet_id                     = var.vnet_subnet_id
  #     private_ip_address_allocation = "static"
  #     private_ip_address            = var.private_ingressgateway_ip
  #   }
  # }
