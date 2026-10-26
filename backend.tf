# backend.tf
# One shared remote state for the whole repository.
#
# Backend settings CANNOT use variables, so fill in the values below (the storage account
# and container must already exist). Then run `terraform init` (or
# `terraform init -migrate-state` if you are moving from local state).
#
# To keep LOCAL state instead for now, comment out the whole `backend "azurerm"` block.

terraform {
  backend "azurerm" {
    resource_group_name  = "RG-TFSTATE"       # <-- change me
    storage_account_name = "statfstateXXXXXX" # <-- change me (globally unique)
    container_name       = "tfstate"          # <-- change me if needed
    key                  = "stark-vm-autostart.tfstate"
    use_azuread_auth     = true
  }
}
