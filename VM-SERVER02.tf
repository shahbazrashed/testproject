############################################################
# VM CONFIGURATION - EDIT THIS SECTION
############################################################
locals {
  server02 = {
    subscription_id     = "MANAGEMENT-SUBSCRIPTION-ID" # reference only; must match the alias used below
    vm_name             = "SERVER02"
    resource_group_name = "RG-MGMT"

    start_hour   = 8
    start_minute = 0
    weekdays     = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]
    time_zone    = "GMT Standard Time" # UK local time - observes BST automatically
  }
}

############################################################
# TERRAFORM RESOURCES - DO NOT MODIFY BELOW UNLESS REQUIRED
# Subscription provider alias for this VM: azurerm.management
############################################################

# Existing VM (looked up, never created or modified)
data "azurerm_virtual_machine" "server02" {
  provider            = azurerm.management
  name                = local.server02.vm_name
  resource_group_name = local.server02.resource_group_name
}

# Existing resource group (used for the Logic App location)
data "azurerm_resource_group" "server02" {
  provider = azurerm.management
  name     = local.server02.resource_group_name
}

# Consumption Logic App, in the VM's resource group, with a system-assigned managed identity
resource "azurerm_logic_app_workflow" "server02" {
  provider            = azurerm.management
  name                = "la-${local.server02.vm_name}-autostart"
  location            = data.azurerm_resource_group.server02.location
  resource_group_name = local.server02.resource_group_name

  identity {
    type = "SystemAssigned"
  }

  tags = {
    managed-by = "terraform"
    purpose    = "vm-autostart"
    vm         = local.server02.vm_name
  }
}

# Weekday recurrence trigger at the configured local time
resource "azurerm_logic_app_trigger_custom" "server02_start" {
  provider     = azurerm.management
  name         = "Recurrence_Start"
  logic_app_id = azurerm_logic_app_workflow.server02.id

  body = jsonencode({
    type = "Recurrence"
    recurrence = {
      frequency = "Week"
      interval  = 1
      timeZone  = local.server02.time_zone
      schedule = {
        hours    = [local.server02.start_hour]
        minutes  = [local.server02.start_minute]
        weekDays = local.server02.weekdays
      }
    }
  })
}

# Managed-identity-authenticated ARM call that starts the VM (no secret, no API connection)
resource "azurerm_logic_app_action_custom" "server02_start" {
  provider     = azurerm.management
  name         = "Start_VM"
  logic_app_id = azurerm_logic_app_workflow.server02.id

  body = jsonencode({
    type = "Http"
    inputs = {
      method = "POST"
      uri    = "https://management.azure.com${data.azurerm_virtual_machine.server02.id}/start?api-version=2024-11-01"
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

  depends_on = [azurerm_logic_app_trigger_custom.server02_start]
}

# RBAC: start permission scoped to the VM itself (least privilege)
resource "azurerm_role_assignment" "server02_start" {
  provider             = azurerm.management
  scope                = data.azurerm_virtual_machine.server02.id
  role_definition_name = "Virtual Machine Contributor"
  principal_id         = azurerm_logic_app_workflow.server02.identity[0].principal_id
  description          = "Allows la-${local.server02.vm_name}-autostart to start ${local.server02.vm_name}."
}

############################################################
# OUTPUTS
############################################################
output "server02_logic_app_name" {
  description = "Logic App that starts SERVER02."
  value       = azurerm_logic_app_workflow.server02.name
}

output "server02_identity_principal_id" {
  description = "Managed identity principal ID for SERVER02's Logic App."
  value       = azurerm_logic_app_workflow.server02.identity[0].principal_id
}

output "server02_start_schedule" {
  description = "When SERVER02 starts."
  value       = format("%02d:%02d %s, %s", local.server02.start_hour, local.server02.start_minute, local.server02.time_zone, join("/", local.server02.weekdays))
}
