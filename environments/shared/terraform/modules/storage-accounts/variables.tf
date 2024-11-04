
variable "accounts" {
  type = list(object(
    {
      name                  = string
      managing_principal_id = string
      target_resource_group = object({
        name     = string
        location = string
      })
      access_tier = string
      blob_properties = optional(object({
        versioning_enabled       = optional(bool, false)
        change_feed_enabled      = optional(bool, false)
        last_access_time_enabled = optional(bool, true)
        delete_retention_policy = optional(object({
          days = number
          }), {
          days = 1
        })
        container_delete_retention_policy = optional(object({
          days = number
          }), {
          days = 1
        })
        }), {
        versioning_enabled       = false
        change_feed_enabled      = false
        last_access_time_enabled = true
        delete_retention_policy = {
          days = 1
        }
        container_delete_retention_policy = {
          days = 1
        }
      })
      containers = optional(list(object({
        name = string
      })), [])
      policies = optional(list(object({
        enabled = optional(bool, true)
        name    = optional(string, "default")
        actions = optional(object({
          base_blob = optional(object({
            auto_tier_to_hot_from_cool_enabled                          = optional(bool)
            tier_to_cool_after_days_since_last_access_time_greater_than = optional(number)
            tier_to_archive_after_days_since_modification_greater_than  = optional(number)
            delete_after_days_since_modification_greater_than           = optional(number)
            delete_after_days_since_last_access_time_greater_than       = optional(number)
            }), {
            base_blob = {
              auto_tier_to_hot_from_cool_enabled                          = true
              tier_to_cool_after_days_since_last_access_time_greater_than = 10 # aggressive for personal account
              tier_to_archive_after_days_since_modification_greater_than  = 20 # aggressive for personal account
              delete_after_days_since_last_access_time_greater_than       = 50 # aggressive for personal account
            }
          })
          }), {
          actions = {
            base_blob = {
              auto_tier_to_hot_from_cool_enabled                          = true
              tier_to_cool_after_days_since_last_access_time_greater_than = 10 # aggressive for personal account
              tier_to_archive_after_days_since_modification_greater_than  = 20 # aggressive for personal account
              delete_after_days_since_last_access_time_greater_than       = 50 # aggressive for personal account
            }
          }
        })
        filters = optional(object({
          blob_types = optional(list(string), ["blockBlob"])
          }), {
          blob_types = ["blockBlob"]
        })
        })), [{
        enabled = true
        name    = "default"
        actions = {
          base_blob = {
            auto_tier_to_hot_from_cool_enabled                          = true
            tier_to_cool_after_days_since_last_access_time_greater_than = 10 # aggressive for personal account
            tier_to_archive_after_days_since_modification_greater_than  = 20 # aggressive for personal account
            delete_after_days_since_last_access_time_greater_than       = 50 # aggressive for personal account
          }
        }
        filters = {
          blob_types = ["blockBlob"]
        }
      }])
    }
  ))
  default = []
}

variable "diagnostics" {
  type = object({
    log_analytics_workspace = object({
      id = string
    })
  })
}
