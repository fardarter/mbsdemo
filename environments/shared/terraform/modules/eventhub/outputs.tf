
output "eventhub" {
  description = "Event Hub (Azapi)"
  value       = azapi_resource.t1mbs_eventhub
}

output "eventhub_namespace" {
  description = "Event Hub Namespace"
  value       = azurerm_eventhub_namespace.t1mbs_eventhub
}


