variable "diagnostics" {
  type = object({
    log_analytics_workspace = object({
      id = string
    })
  })
}

variable "resource_groups" {
  type = object({
    target = object({
      name     = string
      location = string
      id       = string
    })
  })
}

variable "eventhub" {
  type = object({
    id = string
  })
}


variable "eventhub_capture_agent" {
  type = object({
    id           = string
    principal_id = string
  })
}

variable "keyvault" {
  type = object({
    name = string
  })
}

variable "subscriptions" {
  type = object({
    t1 = object({
      id = string
    })
  })
}

variable "clients" {
  type = object({
    clients = list(object({
      name = string
      type = string
    })),
    client_groups = list(object({
      name        = string
      description = string
      query       = string
    })),
  })
}

variable "topics" {
  type = object({
    topic_spaces = list(object({
      name        = string
      description = string
      templates   = list(string)
    })),
    permission_bindings = list(object({
      clientGroupName = string
      description     = string
      topicSpaceName  = string
      permission      = string
    }))
  })
}

variable "admin_user_oid" {
  type = string
}

variable "eventgrid_namespace" {
  nullable = false
  type = object({
    routingEnrichments = optional(
      object({
        dynamic = optional(
          list(object({
            key   = string,
            value = string
        })), [])
        static = optional(
          list(object({
            key       = string,
            value     = string,
            valueType = string
        })), [])
        }), {
        routingEnrichments = {
          dynamic = []
          static  = []
        }
    })
  })
}


