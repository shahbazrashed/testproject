# STARK VM Auto Start — Terraform Implementation Instructions

## 1. Objective

I want you to restructure my existing Terraform code for automatically starting Azure Virtual Machines using Azure Logic Apps.

**My primary requirement is simplicity, readability, and minimal configuration when adding another VM.**

I want to manage multiple existing Azure VMs across different Azure subscriptions using:

- One Terraform repository.
- One shared Terraform state file.
- One `.tf` file per VM.
- One shared `providers.tf` containing subscription-specific provider aliases.
- No Terraform modules.
- Independent startup schedules for each VM.

Do not introduce additional abstraction, modules, or unnecessary complexity.

## 2. Repository Structure

Use the following structure:

```text
STARK-VM-Auto-Start/
│
├── backend.tf
├── versions.tf
├── providers.tf
│
├── VM-SERVER01.tf
├── VM-SERVER02.tf
├── VM-SERVER03.tf
│
└── README.md
```

Each VM-specific file must contain all the Terraform resources required to configure that VM's automatic startup.

For example:

- `VM-SERVER01.tf` manages SERVER01's startup automation.
- `VM-SERVER02.tf` manages SERVER02's startup automation.
- `VM-SERVER03.tf` manages SERVER03's startup automation.

All files share the same Terraform state.

## 3. Multiple Azure Subscriptions — Provider Configuration

This is an important requirement.

The existing VMs are distributed across multiple Azure subscriptions.

Create a single shared `providers.tf` file containing explicitly configured AzureRM provider aliases.

For example:

```hcl
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
```

Use the existing authentication mechanism and appropriate provider version requirements.

### Provider assignment

Each VM must use the correct subscription-specific provider alias.

For example:

| VM | Subscription | Terraform provider |
|---|---|---|
| SERVER01 | Connectivity | `azurerm.connectivity` |
| SERVER02 | Management | `azurerm.management` |
| SERVER03 | Identity | `azurerm.identity` |

All AzureRM resources and data sources associated with a VM must explicitly reference the appropriate provider alias.

Example:

```hcl
resource "azurerm_logic_app_workflow" "server01" {
  provider = azurerm.connectivity

  # Remaining configuration
}
```

**Important:** Terraform cannot dynamically select provider aliases using local variables or expressions.

Therefore, use explicit provider aliases rather than attempting dynamic provider selection.

When copying an existing VM file to create another VM configuration, the provider alias must be updated wherever it appears in that file.

Do not create additional providers inside individual VM files.

## 4. Configuration Values at the Top of Each VM File

This is one of my most important requirements.

When opening a VM's `.tf` file, I want all the values that I need to supply or change grouped together at the very top.

Use a clearly labeled configuration section.

Example:

```hcl
################################################
# VM CONFIGURATION - EDIT THIS SECTION
################################################

locals {
  server01 = {
    subscription_id     = "CONNECTIVITY-SUBSCRIPTION-ID"
    vm_name             = "SERVER01"
    resource_group_name = "RG-SERVERS"

    start_hour          = 7
    start_minute        = 30
    time_zone           = "GMT Standard Time"
  }
}

################################################
# TERRAFORM RESOURCES
# DO NOT MODIFY BELOW UNLESS REQUIRED
################################################
```

These configuration values must be referenced throughout the remaining Terraform resources.

Do not repeatedly hardcode VM names, resource group names, schedules, or subscription IDs.

The subscription ID in this section is for reference and must match the subscription configured for the selected provider alias.

Use the VM name to derive other Azure resource names wherever possible.

## 5. Existing Azure Infrastructure

The Azure VMs and their resource groups already exist.

They are not managed by this Terraform repository.

Terraform must not attempt to:

- Create or recreate the existing VMs.
- Modify VM hardware or operating system settings.
- Recreate the existing resource groups.
- Manage existing VM networking, disks, or other infrastructure.

Use AzureRM data sources where appropriate to reference the existing VM.

Terraform should manage only the resources required to automatically start that VM.

## 6. One Complete Terraform File Per VM

Each VM file must contain all resources required for that VM's startup automation.

For example, `VM-SERVER01.tf` must contain:

1. VM configuration values at the top.
2. Existing VM data source.
3. Logic App workflow.
4. Recurrence trigger.
5. Action to start the VM.
6. Managed identity configuration.
7. Required RBAC role assignments.
8. VM-specific outputs, if needed.

All resources must use the correct provider alias.

Do not create shared modules.

Do not put VM-specific resources in separate files.

Use unique Terraform resource identifiers for each VM so multiple files can coexist within the same root module without naming conflicts.

## 7. Independent VM Schedules

Each VM must have its own independent startup schedule.

Example:

| VM | Start time | Time zone |
|---|---|---|
| SERVER01 | 07:30 | UK |
| SERVER02 | 08:00 | UK |
| SERVER03 | 06:45 | UK |

The schedule must be configured at the top of each VM file.

Use the appropriate Logic App recurrence configuration.

Support the configured time zone, including UK daylight saving time.

Do not hardcode UTC where a local time zone is specified.

Each Logic App must operate independently from the others.

## 8. Resource Naming Convention

Use the existing VM name when generating names for the supporting Azure resources.

Example:

```text
Existing VM:
SERVER01

Logic App:
la-SERVER01-autostart
```

Apply a consistent naming convention to other supporting resources where appropriate.

Ensure names meet Azure resource naming restrictions.

Terraform resource identifiers must also be unique for each VM.

## 9. Shared Terraform State

Use a single remote Terraform state file for the entire repository.

All VM-specific Terraform files must use the same backend.

Do not create separate state files, Terraform workspaces, or root configurations for individual VMs.

However:

- Each VM must have its own independent Logic App.
- Each VM must have its own recurrence schedule.
- VM-specific resources must not unnecessarily depend on other VMs.
- Updating one VM's schedule should normally affect only that VM's automation resources.

I understand that a shared state means a configuration or planning error in one VM file can prevent a full Terraform plan or apply.

That limitation is acceptable.

## 10. Adding a New VM

The process for adding another VM should be as simple as possible.

I want to:

1. Copy an existing VM `.tf` file.
2. Rename the file to match the new VM.
3. Update the VM name, resource group, subscription ID, and schedule in the configuration section at the top.
4. Update the provider alias throughout the file to match the target subscription.
5. Rename VM-specific Terraform resource identifiers to avoid duplicate declarations.
6. Run `terraform plan` and `terraform apply`.

No Terraform module should be required.

No existing VM-specific file should need modification.

If a new Azure subscription is introduced, add its provider alias to the shared `providers.tf`.

## 11. Security and Permissions

Use managed identity for the Logic App where supported.

Grant the minimum required Azure RBAC permissions for starting the VM.

Prefer VM-level role assignment scope rather than subscription-wide permissions.

Avoid embedding passwords, secrets, or access keys in Terraform code.

Ensure the Logic App identity has the required permissions before executing the VM start operation.

## 12. Important Implementation Requirements

- Keep the existing working Logic App startup mechanism unless a change is necessary.
- Do not replace working code with an unnecessarily complicated alternative.
- Do not use Terraform modules.
- Do not use `for_each` to generate all VM automations from a centralized collection.
- Do not use dynamic provider selection.
- Do not create one combined file containing all VMs.
- Do not introduce additional state files.
- Do not create VM infrastructure that already exists.
- Keep the code easy to understand and troubleshoot.
- Use explicit provider aliases consistently across all VM-specific resources and data sources.
- Format all Terraform files using `terraform fmt`.
- Validate the configuration using `terraform validate` where possible.
- Do not claim validation succeeded if the environment prevented it.

## 13. Deliverables

Provide:

1. The proposed repository structure.
2. A complete example of `providers.tf` containing Connectivity, Management, and Identity subscription aliases.
3. One complete, working VM Terraform file containing all its automation resources.
4. A second example VM file using a different subscription alias and schedule.
5. A README explaining how to add another VM.
6. Any required migration guidance if existing resources are already managed in Terraform state.

## 14. Before Implementation

**Do not immediately rewrite the entire repository.**

First, inspect the existing Terraform code and show me:

- The proposed final file structure.
- The shared `providers.tf`.
- One complete example VM file.
- How to copy that file to support another VM in a different subscription.

Wait for my approval before implementing the changes.

The overriding principle is:

**One repository, one shared state, one file per VM, all editable configuration at the top, explicit subscription provider aliases, and absolutely no Terraform modules.**

---

## Implementation notes (as built)

- Layout delivered under `vm-autostart/`: `backend.tf`, `versions.tf`, `providers.tf`, `VM-SERVER01.tf`, `VM-SERVER02.tf`, `VM-SERVER03.tf`, `README.md`. No modules.
- Providers: aliased `connectivity` / `management` / `identity`, no default provider; every resource and data source sets `provider = azurerm.<alias>` explicitly.
- Each VM file has a `locals.<server>` config block on top (subscription_id reference, vm_name, resource_group_name, start_hour, start_minute, weekdays, time_zone) referenced throughout.
- Logic App named `la-<VM>-autostart`, created in the VM's resource group, system-assigned managed identity, weekday `Recurrence` trigger using `GMT Standard Time` (UK local, observes BST), one managed-identity ARM HTTP `POST .../start` action with exponential retry, and a `Virtual Machine Contributor` role assignment scoped to the VM (least privilege).
- Schedules: SERVER01 07:30 (connectivity), SERVER02 08:00 (management), SERVER03 06:45 (identity).
- State: single shared remote backend in `backend.tf` (fill in storage account details; comment out for local state).
