############################################################
# VM CONFIGURATION - EDIT THIS SECTION
############################################################
locals {
  server01 = {
    subscription_id     = "CONNECTIVITY-SUBSCRIPTION-ID" # reference only; must match the alias used below
    vm_name             = "SERVER01"
    resource_group_name = "RG-SERVERS"

    start_hour   = 7
    start_minute = 30
    weekdays     = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]
    time_zone    = "GMT Standard Time" # UK local time - observes BST automatically
  }
}

############################################################
# TERRAFORM RESOURCES - DO NOT MODIFY BELOW UNLESS REQUIRED
# Subscription provider alias for this VM: azurerm.connectivity
############################################################

# Existing VM (looked up, never created or modified)
data "azurerm_virtual_machine" "server01" {
  provider            = azurerm.connectivity
  name                = local.server01.vm_name
  resource_group_name = local.server01.resource_group_name
}

# Existing resource group (used for the Logic App location)
data "azurerm_resource_group" "server01" {
  provider = azurerm.connectivity
  name     = local.server01.resource_group_name
}

# Consumption Logic App, in the VM's resource group, with a system-assigned managed identity
resource "azurerm_logic_app_workflow" "server01" {
  provider            = azurerm.connectivity
  name                = "la-${local.server01.vm_name}-autostart"
  location            = data.azurerm_resource_group.server01.location
  resource_group_name = local.server01.resource_group_name

  identity {
    type = "SystemAssigned"
  }

  tags = {
    managed-by = "terraform"
    purpose    = "vm-autostart"
    vm         = local.server01.vm_name
  }
}

# Weekday recurrence trigger at the configured local time
resource "azurerm_logic_app_trigger_custom" "server01_start" {
  provider     = azurerm.connectivity
  name         = "Recurrence_Start"
  logic_app_id = azurerm_logic_app_workflow.server01.id

  body = jsonencode({
    type = "Recurrence"
    recurrence = {
      frequency = "Week"
      interval  = 1
      timeZone  = local.server01.time_zone
      schedule = {
        hours    = [local.server01.start_hour]
        minutes  = [local.server01.start_minute]
        weekDays = local.server01.weekdays
      }
    }
  })
}

# Managed-identity-authenticated ARM call that starts the VM (no secret, no API connection)
resource "azurerm_logic_app_action_custom" "server01_start" {
  provider     = azurerm.connectivity
  name         = "Start_VM"
  logic_app_id = azurerm_logic_app_workflow.server01.id

  body = jsonencode({
    type = "Http"
    inputs = {
      method = "POST"
      uri    = "https://management.azure.com${data.azurerm_virtual_machine.server01.id}/start?api-version=2024-11-01"
      authentication = {
        type     = "ManagedServiceIdentity"
        audience = "https://management.azure.com/"
      }
      retryPolicy = {
        type     = "exponential"
        count    = 4
        interval = "PT20S"
      }
    }
    runAfter = {}
  })

  depends_on = [azurerm_logic_app_trigger_custom.server01_start]
}

# RBAC: start permission scoped to the VM itself (least privilege)
resource "azurerm_role_assignment" "server01_start" {
  provider             = azurerm.connectivity
  scope                = data.azurerm_virtual_machine.server01.id
  role_definition_name = "Virtual Machine Contributor"
  principal_id         = azurerm_logic_app_workflow.server01.identity[0].principal_id
  description          = "Allows la-${local.server01.vm_name}-autostart to start ${local.server01.vm_name}."
}

############################################################
# OUTPUTS
############################################################
output "server01_logic_app_name" {
  description = "Logic App that starts SERVER01."
  value       = azurerm_logic_app_workflow.server01.name
}

output "server01_identity_principal_id" {
  description = "Managed identity principal ID for SERVER01's Logic App."
  value       = azurerm_logic_app_workflow.server01.identity[0].principal_id
}

output "server01_start_schedule" {
  description = "When SERVER01 starts."
  value       = format("%02d:%02d %s, %s", local.server01.start_hour, local.server01.start_minute, local.server01.time_zone, join("/", local.server01.weekdays))
}
