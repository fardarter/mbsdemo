terraform {
  required_providers {
    azapi = {
      source  = "Azure/azapi"
      version = "2.0.1"
    }
  }
}

resource "azurerm_eventgrid_topic" "eventgrid_topic_cloudevents" {
  #checkov:skip=CKV_AZURE_193:Private networking not implemented for demo
  name                          = "cloudeventsv10"
  location                      = "westeurope"
  resource_group_name           = var.resource_groups.target.name
  input_schema                  = "CloudEventSchemaV1_0"
  public_network_access_enabled = true
  local_auth_enabled            = false
  identity {
    type         = "UserAssigned"
    identity_ids = [var.eventhub_capture_agent.id]
  }
}

resource "azurerm_eventgrid_event_subscription" "device_messages" {
  name                                 = "iotgriddevicemessages"
  scope                                = azurerm_eventgrid_topic.eventgrid_topic_cloudevents.id
  eventhub_endpoint_id                 = var.eventhub.id
  event_delivery_schema                = "CloudEventSchemaV1_0"
  included_event_types                 = ["MQTT.EventPublished"]
  advanced_filtering_on_arrays_enabled = true
  advanced_filter {
    string_in {
      key    = "source"
      values = ["t1mbs-eventgrid-namespace"]
    }
    string_in {
      key    = "egnssource"
      values = ["iotgrid"]
    }
  }
  subject_filter {
    subject_begins_with = "device"
    case_sensitive      = true
  }

  delivery_identity {
    type                   = "UserAssigned"
    user_assigned_identity = var.eventhub_capture_agent.id
  }
}

resource "azurerm_role_assignment" "admin_eventgrid_data_sender" {
  scope                            = azurerm_eventgrid_topic.eventgrid_topic_cloudevents.id
  role_definition_name             = "EventGrid Data Sender"
  principal_id                     = var.admin_user_oid
  skip_service_principal_aad_check = false
}

resource "azurerm_role_assignment" "eventgrid_topic_msi_agent_grid_sender_rights" {
  scope                            = azurerm_eventgrid_topic.eventgrid_topic_cloudevents.id
  role_definition_name             = "EventGrid Data Sender"
  principal_id                     = var.eventhub_capture_agent.principal_id
  skip_service_principal_aad_check = true
}

resource "azapi_resource" "eventgrid_namespace" {
  # azapi is a escape hatch. this should be converted as soon as the resource is available via azurerm
  # See: https://learn.microsoft.com/en-us/azure/templates/microsoft.eventgrid/namespaces?pivots=deployment-language-terraform
  type      = "Microsoft.EventGrid/namespaces@2023-12-15-preview"
  name      = "t1mbs-eventgrid-namespace"
  location  = "westeurope"
  parent_id = var.resource_groups.target.id

  identity {
    type         = "SystemAssigned, UserAssigned"
    identity_ids = [var.eventhub_capture_agent.id]
  }

  body = {
    properties = {
      publicNetworkAccess = "Enabled"
      topicSpacesConfiguration = {
        state                = "Enabled",
        routeTopicResourceId = azurerm_eventgrid_topic.eventgrid_topic_cloudevents.id
        routingEnrichments   = var.eventgrid_namespace.routingEnrichments
        routingIdentityInfo = {
          type                 = "UserAssigned"
          userAssignedIdentity = var.eventhub_capture_agent.id
        }
      }
    }
    sku = {
      capacity = 1
      name     = "Standard"
    }
  }
  depends_on = [azurerm_role_assignment.eventgrid_topic_msi_agent_grid_sender_rights]
}


resource "azurerm_role_assignment" "agent_umi_eventgrid_namespace_sender_rights" {
  scope                            = azapi_resource.eventgrid_namespace.id
  role_definition_name             = "Azure Event Hubs Data Sender"
  principal_id                     = var.eventhub_capture_agent.principal_id
  skip_service_principal_aad_check = true
}

resource "terraform_data" "create_ca_cert" {
  triggers_replace = [
    azapi_resource.eventgrid_namespace.id, "trigger-value"
  ]
  provisioner "local-exec" {
    # Provisioner used to prevent storage of secret in state. 
    # For a production scenario, we'd need to implement some kind of change detection
    # eg, triggering on secret creation time changes. 
    # Renewal would need external automation or a scheduled drift restriction run.
    interpreter = ["bash", "-c"]
    command     = <<-EOT

        trap 'rm ./intermediate-ca.crt' EXIT

        az extension add --name eventgrid --allow-preview true

        az keyvault secret show \
        --name "intermediate-ca-crt" \
        --vault-name ${var.keyvault.name} \
        --query "value" -o tsv | base64 -di | tr -d '\n' > ./intermediate-ca.crt

        az eventgrid namespace ca-certificate create \
        --resource-group ${var.resource_groups.target.name} \
        --namespace-name ${azapi_resource.eventgrid_namespace.name} \
        -n intermediate-ca \
        --subscription ${var.subscriptions.t1.id} \
        --certificate ./intermediate-ca.crt > /dev/null

  EOT
  }
}

resource "azapi_resource" "client_groups" {
  for_each = { for item in var.clients.client_groups : lower(item.name) => item }
  # https://learn.microsoft.com/en-us/azure/templates/microsoft.eventgrid/namespaces/clientgroups?pivots=deployment-language-terraform
  type      = "Microsoft.EventGrid/namespaces/clientGroups@2023-12-15-preview"
  name      = each.value.name
  parent_id = azapi_resource.eventgrid_namespace.id
  body = {
    properties = {
      description = each.value.description
      query       = each.value.query
    }
  }
}

resource "azapi_resource" "eventgrid_namespace_client" {
  for_each = { for item in var.clients.clients : lower(item.name) => item }
  type     = "Microsoft.EventGrid/namespaces/clients@2023-12-15-preview"
  # https://learn.microsoft.com/en-us/azure/templates/microsoft.eventgrid/namespaces/clients?pivots=deployment-language-terraform
  name      = each.value.name
  parent_id = azapi_resource.eventgrid_namespace.id
  body = {
    properties = {
      attributes         = { type = each.value.type }
      authenticationName = "${each.value.name}-authn-ID"
      clientCertificateAuthentication = {
        validationScheme = "SubjectMatchesAuthenticationName"
      }
      description = "MBSDemo test client"
      state       = "Enabled"
    }
  }
}

resource "azapi_resource" "eventgrid_namespace_topic_space" {
  for_each = { for item in var.topics.topic_spaces : lower(item.name) => item }
  type     = "Microsoft.EventGrid/namespaces/topicSpaces@2023-12-15-preview"
  # https://learn.microsoft.com/en-us/azure/templates/microsoft.eventgrid/namespaces/topicspaces?pivots=deployment-language-terraform
  name      = each.value.name
  parent_id = azapi_resource.eventgrid_namespace.id
  body = {
    properties = {
      description    = each.value.description
      topicTemplates = each.value.templates
    }
  }
}

resource "azapi_resource" "eventgrid_namespace_permission_bindings" {
  for_each = { for item in var.topics.permission_bindings : lower("${item.topicSpaceName}-${item.permission}") => item }
  # https://learn.microsoft.com/en-us/azure/templates/microsoft.eventgrid/namespaces/permissionbindings?pivots=deployment-language-terraform
  type      = "Microsoft.EventGrid/namespaces/permissionBindings@2023-12-15-preview"
  name      = replace(each.value.description, " ", "")
  parent_id = azapi_resource.eventgrid_namespace.id
  body = {
    properties = {
      clientGroupName = azapi_resource.client_groups[lower("${each.value.clientGroupName}")].name
      description     = each.value.description
      permission      = each.value.permission
      topicSpaceName  = azapi_resource.eventgrid_namespace_topic_space[lower("${each.value.topicSpaceName}")].name
    }
  }
}

resource "azurerm_eventgrid_system_topic" "t1mbs_mqtt" {
  name                   = "t1mbs-mqtt-system-topic"
  resource_group_name    = var.resource_groups.target.name
  location               = "westeurope"
  source_arm_resource_id = azapi_resource.eventgrid_namespace.id
  topic_type             = "Microsoft.EventGrid.Namespaces"
  identity {
    type         = "UserAssigned"
    identity_ids = [var.eventhub_capture_agent.id]
  }
}

resource "azurerm_eventgrid_event_subscription" "mqttsystemtopics" {
  name                  = "mqttsystemtopics"
  scope                 = azapi_resource.eventgrid_namespace.id
  eventhub_endpoint_id  = var.eventhub.id
  event_delivery_schema = "EventGridSchema"
  included_event_types = [
    "Microsoft.EventGrid.MQTTClientSessionConnected",
    "Microsoft.EventGrid.MQTTClientSessionDisconnected",
    "Microsoft.EventGrid.MQTTClientCreatedOrUpdated",
    "Microsoft.EventGrid.MQTTClientDeleted"
  ]
  advanced_filtering_on_arrays_enabled = true
  delivery_identity {
    type                   = "UserAssigned"
    user_assigned_identity = var.eventhub_capture_agent.id
  }
}


data "azurerm_monitor_diagnostic_categories" "eventgrid_topic" {
  resource_id = azurerm_eventgrid_topic.eventgrid_topic_cloudevents.id
}

data "azurerm_monitor_diagnostic_categories" "eventgrid_system_topic" {
  resource_id = azurerm_eventgrid_system_topic.t1mbs_mqtt.id
}


data "azurerm_monitor_diagnostic_categories" "eventgrid_namespace" {
  resource_id = azapi_resource.eventgrid_namespace.id
}



resource "azurerm_monitor_diagnostic_setting" "eventgrid_topic_diagnostic_setting" {
  name                       = "t0-control-plane-law"
  target_resource_id         = azurerm_eventgrid_topic.eventgrid_topic_cloudevents.id
  log_analytics_workspace_id = var.diagnostics.log_analytics_workspace.id

  dynamic "enabled_log" {
    for_each = try(data.azurerm_monitor_diagnostic_categories.eventgrid_topic.log_category_types, [])
    content {
      category = enabled_log.value
    }
  }

  dynamic "metric" {
    for_each = try(data.azurerm_monitor_diagnostic_categories.eventgrid_topic.metrics, [])
    content {
      category = metric.value
      enabled  = true
    }
  }
}

resource "azurerm_monitor_diagnostic_setting" "eventgrid_system_topic_diagnostic_setting" {
  name                       = "t0-control-plane-law"
  target_resource_id         = azurerm_eventgrid_system_topic.t1mbs_mqtt.id
  log_analytics_workspace_id = var.diagnostics.log_analytics_workspace.id

  dynamic "enabled_log" {
    for_each = try(data.azurerm_monitor_diagnostic_categories.eventgrid_system_topic.log_category_types, [])
    content {
      category = enabled_log.value
    }
  }

  dynamic "metric" {
    for_each = try(data.azurerm_monitor_diagnostic_categories.eventgrid_system_topic.metrics, [])
    content {
      category = metric.value
      enabled  = true
    }
  }
}

resource "azurerm_monitor_diagnostic_setting" "eventgrid_namespace_diagnostic_setting" {
  name                       = "t0-control-plane-law"
  target_resource_id         = azapi_resource.eventgrid_namespace.id
  log_analytics_workspace_id = var.diagnostics.log_analytics_workspace.id

  dynamic "enabled_log" {
    for_each = try(data.azurerm_monitor_diagnostic_categories.eventgrid_namespace.log_category_types, [])
    content {
      category = enabled_log.value
    }
  }

  dynamic "metric" {
    for_each = try(data.azurerm_monitor_diagnostic_categories.eventgrid_namespace.metrics, [])
    content {
      category = metric.value
      enabled  = true
    }
  }
}
