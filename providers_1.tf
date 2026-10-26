# providers.tf
# One AzureRM provider per subscription, each with an explicit alias. There is deliberately
# NO default (unaliased) provider: every resource and data source in the VM files sets
# `provider = azurerm.<alias>` explicitly, so each VM is pinned to the right subscription.
#
# Authentication is taken from the environment (az login, ARM_* env vars, workload/managed
# identity). No secrets are stored here. Add a new aliased provider when you introduce a new
# subscription.

provider "azurerm" {
  alias           = "connectivity"
  subscription_id = "CONNECTIVITY-SUBSCRIPTION-ID"

  features {}
}

provider "azurerm" {
  alias           = "management"
  subscription_id = "MANAGEMENT-SUBSCRIPTION-ID"

  features {}
}

provider "azurerm" {
  alias           = "identity"
  subscription_id = "IDENTITY-SUBSCRIPTION-ID"

  features {}
}
