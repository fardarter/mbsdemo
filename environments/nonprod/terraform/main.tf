terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.8.0"
    }
    azapi = {
      source  = "Azure/azapi"
      version = "2.0.1"
    }
  }

  required_version = ">= 1.9.8"

  backend "azurerm" {
    resource_group_name  = "t0-control-plane"
    storage_account_name = "slnt0iac"
    container_name       = "tier1"
    key                  = "mercedes.nonprod.terraform.tfstate"
    use_azuread_auth     = true
    use_oidc             = true
  }
}

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = true
    }
  }
  resource_provider_registrations = "none"
  storage_use_azuread             = true
}

provider "azurerm" {
  alias           = "t0"
  subscription_id = "b607efe4-d22a-4a38-ab53-9cc36a06ea37"

  features {
    resource_group {
      prevent_deletion_if_contains_resources = true
    }
  }
  resource_provider_registrations = "none"
  storage_use_azuread             = true
}

provider "azapi" {
  enable_preflight = true
}

data "azurerm_resource_group" "mercedes_benz" {
  name = "mercedes-benz"
}

data "azurerm_log_analytics_workspace" "t0law" {
  provider            = azurerm.t0
  name                = "t0-control-plane-law"
  resource_group_name = "t0-control-plane"
}

data "azurerm_client_config" "current" {}

locals {
  destroy_all     = false
  MBSDemoGroupOID = "01b0323d-c378-4814-8ffa-526dc24a8172"
  resource_groups = {
    t1control = "t1-control-plane"
  }
  storage_accounts = [
    {
      name                  = "slnt1mbscapture"
      access_tier           = "Hot"
      target_resource_group = data.azurerm_resource_group.mercedes_benz
      managing_principal_id = data.azurerm_client_config.current.object_id
      containers = [
        {
          name = "t1eventhub-capture"
        }
      ]
    },
  ]
}

data "azurerm_user_assigned_identity" "t1mbs_eventhub_capture_agent" {
  name                = "t1-mercedes-benz-iothub-eventhub-namespace-agent"
  resource_group_name = local.resource_groups.t1control

}

module "storage_accounts" {
  count  = local.destroy_all ? 0 : 1
  source = "../../shared/terraform/modules/storage-accounts"
  diagnostics = {
    log_analytics_workspace = data.azurerm_log_analytics_workspace.t0law
  }
  accounts = local.storage_accounts
}

resource "azurerm_role_assignment" "event_hub_agent_rg_storage_rights" {
  scope                            = data.azurerm_resource_group.mercedes_benz.id
  role_definition_name             = "Storage Blob Data Owner"
  principal_id                     = data.azurerm_user_assigned_identity.t1mbs_eventhub_capture_agent.principal_id
  skip_service_principal_aad_check = true
}

data "azurerm_key_vault" "t1mbs" {
  name                = "t1mbs-kv"
  resource_group_name = local.resource_groups.t1control
}

module "eventhub" {
  count  = local.destroy_all ? 0 : 1
  source = "../../shared/terraform/modules/eventhub"
  diagnostics = {
    log_analytics_workspace = data.azurerm_log_analytics_workspace.t0law
  }
  resource_groups = { target = data.azurerm_resource_group.mercedes_benz }
  storage = {
    agent             = data.azurerm_user_assigned_identity.t1mbs_eventhub_capture_agent
    capture_account   = module.storage_accounts[0].accounts["slnt1mbscapture"]
    capture_container = module.storage_accounts[0].containers["slnt1mbscapture.t1eventhub-capture"]
  }
}

locals {
  admin_user_oid = "33a8c965-0b43-47e2-89d1-abe6aa3d9e4a"
  client_groups = [
    { name = "senders", query = "attributes.type in ['sender']", description = "Has attribute sender" },
    { name = "receivers", query = "attributes.type in ['receiver']", description = "Has attribute receiver" }
  ]
  clients = [
    { name = "client1", type = "sender" },
    { name = "client2", type = "sender" },
    { name = "client3", type = "receiver" },
    { name = "client4", type = "receiver" },
    { name = "client5", type = "receiver" },
  ]
  topic_spaces = [
    {
      name        = "Senders",
      description = "Senders with spoof protection via $${client.authenticationName} template"
      templates = [
        "device/$${client.authenticationName}/telemetry"
      ]
    },
    {
      name        = "Receivers",
      description = "Receivers"
      templates = [
        "device/+/telemetry"
      ]
    },
  ]
  permission_bindings = [
    {
      clientGroupName = "senders",
      description     = "Senders",
      topicSpaceName  = "Senders",
      permission      = "Publisher"
    },
    {
      clientGroupName = "receivers",
      description     = "Receivers",
      topicSpaceName  = "Receivers",
      permission      = "Subscriber"
    }
  ]
  routingEnrichments = {
    dynamic = [
      { key = "devicetype", value = "$${client.attributes.type}" },
    ]
    static = [
      {
        key       = "egnssource"
        valueType = "String"
        value     = "iotgrid"
      }
    ]
  }
}

module "mqttbroker" {
  count  = local.destroy_all ? 0 : 1
  source = "../../shared/terraform/modules/mqttbroker"
  diagnostics = {
    log_analytics_workspace = data.azurerm_log_analytics_workspace.t0law
  }
  resource_groups        = { target = data.azurerm_resource_group.mercedes_benz }
  eventhub               = module.eventhub[0].eventhub
  eventhub_capture_agent = data.azurerm_user_assigned_identity.t1mbs_eventhub_capture_agent
  subscriptions = {
    t1 = {
      id = "11969dcb-798a-4df5-9801-49437e80c225"
    }
  }
  keyvault = data.azurerm_key_vault.t1mbs
  clients = {
    clients       = local.clients
    client_groups = local.client_groups
  }
  topics = {
    topic_spaces        = local.topic_spaces
    permission_bindings = local.permission_bindings
  }
  admin_user_oid = local.admin_user_oid
  eventgrid_namespace = {
    routingEnrichments = local.routingEnrichments
  }
}

resource "azurerm_role_assignment" "mbs_demo_storage_reader" {
  count                            = local.destroy_all ? 0 : 1
  scope                            = module.storage_accounts[0].accounts["slnt1mbscapture"].id
  role_definition_name             = "Storage Blob Data Reader"
  principal_id                     = local.MBSDemoGroupOID
  skip_service_principal_aad_check = false
}

resource "azurerm_role_assignment" "mbs_demo_egsub_reader" {
  scope                            = data.azurerm_resource_group.mercedes_benz.id
  role_definition_name             = "EventGrid EventSubscription Reader"
  principal_id                     = local.MBSDemoGroupOID
  skip_service_principal_aad_check = false
}

resource "azurerm_role_assignment" "mbs_demo_monitoring_reader" {
  scope                            = data.azurerm_resource_group.mercedes_benz.id
  role_definition_name             = "Monitoring Reader"
  principal_id                     = local.MBSDemoGroupOID
  skip_service_principal_aad_check = false
}

resource "azurerm_role_assignment" "mbs_demo_saqt" {
  scope                            = data.azurerm_resource_group.mercedes_benz.id
  role_definition_name             = "Stream Analytics Query Tester"
  principal_id                     = local.MBSDemoGroupOID
  skip_service_principal_aad_check = false
}

resource "azurerm_role_assignment" "mbs_demo_aehdr" {
  scope                            = data.azurerm_resource_group.mercedes_benz.id
  role_definition_name             = "Azure Event Hubs Data Receiver"
  principal_id                     = local.MBSDemoGroupOID
  skip_service_principal_aad_check = false
}

resource "azurerm_role_assignment" "mbs_demo_aehds" {
  scope                            = data.azurerm_resource_group.mercedes_benz.id
  role_definition_name             = "Azure Event Hubs Data Sender"
  principal_id                     = local.MBSDemoGroupOID
  skip_service_principal_aad_check = false
}

resource "azurerm_role_assignment" "mbs_demo_egds" {
  scope                            = data.azurerm_resource_group.mercedes_benz.id
  role_definition_name             = "EventGrid TopicSpaces Subscriber"
  principal_id                     = local.MBSDemoGroupOID
  skip_service_principal_aad_check = false
}


