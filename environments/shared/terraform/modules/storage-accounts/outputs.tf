output "accounts" {
  description = "Storage accounts"
  value       = azurerm_storage_account.account
}

output "containers" {
  description = "Storage containers"
  value       = azurerm_storage_container.container
}
