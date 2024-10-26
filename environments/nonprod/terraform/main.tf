terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.6.0"
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
  resource_provider_registrations = "extended"
  storage_use_azuread             = true
}

data "azurerm_resource_group" "mercedes_benz" {
  name = "mercedes-benz"
}

data "azurerm_log_analytics_workspace" "global" {
  name                = "t0-control-plane-law"
  resource_group_name = "t0-control-plane"
}

resource "terraform_data" "test" {
  input = "test"
}
