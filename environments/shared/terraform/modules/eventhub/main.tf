terraform {
  required_providers {
    azapi = {
      source  = "Azure/azapi"
      version = "2.0.1"
    }
  }
}

locals {
  with_capture = true
}

resource "azurerm_eventhub_namespace" "t1mbs_eventhub" {
  name                          = "t1mbs-eventhub-ehn"
  resource_group_name           = var.resource_groups.target.name
  location                      = var.resource_groups.target.location
  sku                           = local.with_capture ? "Standard" : "Basic"
  public_network_access_enabled = true # ideal case would involve private endpoints
  local_authentication_enabled  = true
  auto_inflate_enabled          = false
  network_rulesets {
    default_action                 = "Allow"
    trusted_service_access_enabled = true
    public_network_access_enabled  = true # ideal case would involve private endpoints
  }
  identity {
    type         = "SystemAssigned, UserAssigned"
    identity_ids = [var.storage.agent.id]
  }
}

resource "azurerm_role_assignment" "agent_umi_eventhub_namespace_sender_rights" {
  scope                            = azurerm_eventhub_namespace.t1mbs_eventhub.id
  role_definition_name             = "Azure Event Hubs Data Sender"
  principal_id                     = var.storage.agent.principal_id
  skip_service_principal_aad_check = true
}

resource "azapi_resource" "t1mbs_eventhub" {
  type      = "Microsoft.EventHub/namespaces/eventhubs@2024-01-01"
  name      = "t1mbs-eventhub-eh"
  parent_id = azurerm_eventhub_namespace.t1mbs_eventhub.id
  body = {
    properties = {
      captureDescription = {
        destination = {
          identity = {
            type                 = "UserAssigned"
            userAssignedIdentity = var.storage.agent.id
          }
          name = "EventHubArchive.AzureBlockBlob"
          properties = {
            archiveNameFormat        = "{Namespace}/{EventHub}/{PartitionId}/{Year}/{Month}/{Day}/{Hour}/{Minute}/{Second}"
            blobContainer            = "t1eventhub-capture"
            storageAccountResourceId = var.storage.capture_account.id
          }
        }
        enabled           = true
        encoding          = "Avro"
        intervalInSeconds = 60
        sizeLimitInBytes  = 10485760
        skipEmptyArchives = true
      }
      messageRetentionInDays = 1
      partitionCount         = 2
    }
  }
}

resource "azurerm_role_assignment" "agent_umi_eventhub_sender_rights" {
  scope                            = azapi_resource.t1mbs_eventhub.id
  role_definition_name             = "Azure Event Hubs Data Sender"
  principal_id                     = var.storage.agent.principal_id
  skip_service_principal_aad_check = true
}

resource "azurerm_eventhub_authorization_rule" "t1mbs_eventhub" {
  resource_group_name = var.resource_groups.target.name
  namespace_name      = azurerm_eventhub_namespace.t1mbs_eventhub.name
  eventhub_name       = azapi_resource.t1mbs_eventhub.name
  name                = "t1mbs-eventhub-ehar"
  send                = true
  listen              = true
  manage              = true
}

data "azurerm_monitor_diagnostic_categories" "event_hub_namespace" {
  resource_id = azurerm_eventhub_namespace.t1mbs_eventhub.id
}


resource "azurerm_monitor_diagnostic_setting" "event_hub_namespace_diagnostic_setting" {
  name                       = "t0-control-plane-law"
  target_resource_id         = azurerm_eventhub_namespace.t1mbs_eventhub.id
  log_analytics_workspace_id = var.diagnostics.log_analytics_workspace.id

  dynamic "enabled_log" {
    for_each = try(data.azurerm_monitor_diagnostic_categories.event_hub_namespace.log_category_types, [])
    content {
      category = enabled_log.value
    }
  }

  dynamic "metric" {
    for_each = try(data.azurerm_monitor_diagnostic_categories.event_hub_namespace.metrics, [])
    content {
      category = metric.value
      enabled  = true
    }
  }
}
