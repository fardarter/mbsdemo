variable "diagnostics" {
  type = object({
    log_analytics_workspace = object({
      id = string
    })
  })
}

variable "storage" {
  type = object({
    capture_account = object({
      id = string
    })
    capture_container = object({
      resource_manager_id = string
    })
    agent = object({
      principal_id = string
      id           = string
    })
  })
}

variable "resource_groups" {
  type = object({
    target = object({
      name     = string
      location = string
    })
  })
}
