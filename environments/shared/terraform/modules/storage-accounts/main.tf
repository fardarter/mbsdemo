resource "azurerm_storage_account" "account" {
  for_each = { for account in var.accounts : account.name => account }
  #checkov:skip=CKV2_AZURE_1:Platform managed key prefered for now
  #checkov:skip=CKV2_AZURE_18:Platform managed key prefered for now
  #checkov:skip=CKV2_AZURE_8:Logging to be done via diagnostics
  #checkov:skip=CKV_AZURE_35:Using RBAC and private containers as auth. Private networking would be ideal.
  #checkov:skip=CKV_AZURE_33:Queue not in use
  #checkov:skip=CKV_AZURE_43:Unclear how to satisfy policy
  #checkov:skip=CKV_AZURE_206:Unclear how to satisfy policy
  #checkov:skip=CKV_AZURE_59:Unclear how to satisfy policy
  #checkov:skip=CKV2_AZURE_33:"Ensure storage account is configured with private endpoint" Access controlled through RBAC
  name                              = each.value.name
  resource_group_name               = each.value.target_resource_group.name
  location                          = each.value.target_resource_group.location
  account_tier                      = "Standard"
  account_replication_type          = "LRS"
  account_kind                      = "StorageV2"
  access_tier                       = each.value.access_tier
  infrastructure_encryption_enabled = true
  shared_access_key_enabled         = false
  https_traffic_only_enabled        = true
  min_tls_version                   = "TLS1_2"
  cross_tenant_replication_enabled  = false
  allow_nested_items_to_be_public   = false
  default_to_oauth_authentication   = true
  local_user_enabled                = false
  is_hns_enabled                    = true

  routing {
    publish_microsoft_endpoints = true
  }
  blob_properties {
    versioning_enabled       = each.value.blob_properties.versioning_enabled
    change_feed_enabled      = each.value.blob_properties.change_feed_enabled
    last_access_time_enabled = each.value.blob_properties.last_access_time_enabled

    delete_retention_policy {
      days = each.value.blob_properties.delete_retention_policy.days
    }
    container_delete_retention_policy {
      days = each.value.blob_properties.container_delete_retention_policy.days
    }
  }
}

resource "azurerm_role_assignment" "account_rights" {
  for_each                         = { for account in var.accounts : account.name => account }
  scope                            = azurerm_storage_account.account[each.value.name].id
  role_definition_name             = "Storage Blob Data Contributor"
  principal_id                     = each.value.managing_principal_id
  skip_service_principal_aad_check = false
}


resource "azurerm_storage_management_policy" "account" {
  for_each           = { for account in var.accounts : account.name => account }
  storage_account_id = azurerm_storage_account.account[each.value.name].id

  dynamic "rule" {
    for_each = toset(each.value.policies)
    content {
      name    = rule.value.name
      enabled = rule.value.enabled
      filters {
        blob_types = rule.value.filters.blob_types
      }
      actions {
        base_blob {
          auto_tier_to_hot_from_cool_enabled                          = rule.value.actions.base_blob.auto_tier_to_hot_from_cool_enabled
          tier_to_cool_after_days_since_last_access_time_greater_than = rule.value.actions.base_blob.tier_to_cool_after_days_since_last_access_time_greater_than
          tier_to_archive_after_days_since_modification_greater_than  = rule.value.actions.base_blob.tier_to_archive_after_days_since_modification_greater_than
          delete_after_days_since_modification_greater_than           = rule.value.actions.base_blob.delete_after_days_since_modification_greater_than
          delete_after_days_since_last_access_time_greater_than       = rule.value.actions.base_blob.delete_after_days_since_last_access_time_greater_than

        }
      }
    }
  }
}

locals {
  containers = flatten([
    for account in var.accounts : [
      for container in account.containers : {
        account_name = account.name
        name         = container.name
      }
    ]
  ])
}

resource "azurerm_storage_container" "container" {
  #ts:skip=AC_AZURE_0366 Anon access is sometimes intentional
  #checkov:skip=CKV2_AZURE_21:Logging to be handled by diagnostic settings
  #checkov:skip=CKV_AZURE_34:"Ensure that 'Public access level' is set to Private for blob containers" Anon access is sometimes intentional
  #ts:skip=AC_AZURE_0389 Locking to be done at a higher maturity level
  for_each             = { for container in local.containers : "${container.account_name}.${container.name}" => container }
  name                 = each.value.name
  storage_account_name = each.value.account_name
  depends_on           = [azurerm_storage_account.account, azurerm_role_assignment.account_rights]
}

data "azurerm_monitor_diagnostic_categories" "blob_service_diagnostic_categories" {
  count       = length(var.accounts) >= 1 ? 1 : 0
  resource_id = "${azurerm_storage_account.account[var.accounts[0].name].id}/blobServices/default/"
}

data "azurerm_monitor_diagnostic_categories" "queue_service_diagnostic_categories" {
  count       = length(var.accounts) >= 1 ? 1 : 0
  resource_id = "${azurerm_storage_account.account[var.accounts[0].name].id}/queueServices/default/"
}

data "azurerm_monitor_diagnostic_categories" "file_service_diagnostic_categories" {
  count       = length(var.accounts) >= 1 ? 1 : 0
  resource_id = "${azurerm_storage_account.account[var.accounts[0].name].id}/fileServices/default/"
}

data "azurerm_monitor_diagnostic_categories" "table_service_diagnostic_categories" {
  count       = length(var.accounts) >= 1 ? 1 : 0
  resource_id = "${azurerm_storage_account.account[var.accounts[0].name].id}/tableServices/default/"
}

data "azurerm_monitor_diagnostic_categories" "base_storage_diagnostic_categories" {
  count       = length(var.accounts) >= 1 ? 1 : 0
  resource_id = "${azurerm_storage_account.account[var.accounts[0].name].id}/"
}

locals {
  diagnostics = {
    base  = try(data.azurerm_monitor_diagnostic_categories.base_storage_diagnostic_categories[0], [])
    queue = try(data.azurerm_monitor_diagnostic_categories.queue_service_diagnostic_categories[0], [])
    blob  = try(data.azurerm_monitor_diagnostic_categories.blob_service_diagnostic_categories[0], [])
    file  = try(data.azurerm_monitor_diagnostic_categories.file_service_diagnostic_categories[0], [])
    table = try(data.azurerm_monitor_diagnostic_categories.table_service_diagnostic_categories[0], [])
  }
}

resource "azurerm_monitor_diagnostic_setting" "account_base_diagnostic_setting" {
  for_each                   = { for account in var.accounts : account.name => account }
  name                       = "t0-control-plane-law"
  target_resource_id         = azurerm_storage_account.account[each.value.name].id
  log_analytics_workspace_id = var.diagnostics.log_analytics_workspace.id

  dynamic "enabled_log" {
    for_each = try(local.diagnostics.base.log_category_types, [])
    content {
      category = enabled_log.value
    }
  }

  dynamic "metric" {
    for_each = try(local.diagnostics.base.metrics, [])
    content {
      category = metric.value
      enabled  = true
    }
  }
}

resource "azurerm_monitor_diagnostic_setting" "account_blob_diagnostic_setting" {
  for_each                   = { for account in var.accounts : account.name => account }
  name                       = "t0-control-plane-law"
  target_resource_id         = "${azurerm_storage_account.account[each.value.name].id}/blobServices/default/"
  log_analytics_workspace_id = var.diagnostics.log_analytics_workspace.id

  dynamic "enabled_log" {
    for_each = try(local.diagnostics.blob.log_category_types, [])
    content {
      category = enabled_log.value
    }
  }

  dynamic "metric" {
    for_each = try(local.diagnostics.blob.metrics, [])
    content {
      category = metric.value
      enabled  = true
    }
  }
}

resource "azurerm_monitor_diagnostic_setting" "account_queue_diagnostic_setting" {
  for_each                   = { for account in var.accounts : account.name => account }
  name                       = "t0-control-plane-law"
  target_resource_id         = "${azurerm_storage_account.account[each.value.name].id}/queueServices/default/"
  log_analytics_workspace_id = var.diagnostics.log_analytics_workspace.id

  dynamic "enabled_log" {
    for_each = try(local.diagnostics.queue.log_category_types, [])
    content {
      category = enabled_log.value
    }
  }

  dynamic "metric" {
    for_each = try(local.diagnostics.queue.metrics, [])
    content {
      category = metric.value
      enabled  = true
    }
  }
}

resource "azurerm_monitor_diagnostic_setting" "account_file_diagnostic_setting" {
  for_each                   = { for account in var.accounts : account.name => account }
  name                       = "t0-control-plane-law"
  target_resource_id         = "${azurerm_storage_account.account[each.value.name].id}/fileServices/default/"
  log_analytics_workspace_id = var.diagnostics.log_analytics_workspace.id

  dynamic "enabled_log" {
    for_each = try(local.diagnostics.file.log_category_types, [])
    content {
      category = enabled_log.value
    }
  }

  dynamic "metric" {
    for_each = try(local.diagnostics.file.metrics, [])
    content {
      category = metric.value
      enabled  = true
    }
  }
}

resource "azurerm_monitor_diagnostic_setting" "account_table_diagnostic_setting" {
  for_each                   = { for account in var.accounts : account.name => account }
  name                       = "t0-control-plane-law"
  target_resource_id         = "${azurerm_storage_account.account[each.value.name].id}/tableServices/default/"
  log_analytics_workspace_id = var.diagnostics.log_analytics_workspace.id

  dynamic "enabled_log" {
    for_each = try(local.diagnostics.table.log_category_types, [])
    content {
      category = enabled_log.value
    }
  }

  dynamic "metric" {
    for_each = try(local.diagnostics.table.metrics, [])
    content {
      category = metric.value
      enabled  = true
    }
  }
}
