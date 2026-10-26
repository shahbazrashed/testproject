# STARK VM Auto-Start (Terraform)

Automatically **start** existing Azure VMs on a weekday schedule, using one Azure
**Consumption Logic App** per VM, authenticated with the Logic App's **system-assigned
managed identity** — no secrets, no API connections, no manual portal "Authorize".

Design principle: **one repository, one shared state, one file per VM, all editable
configuration at the top of each file, explicit subscription provider aliases, no Terraform
modules.**

## Layout

```text
STARK-VM-Auto-Start/
├── backend.tf        # one shared remote state for the whole repo
├── versions.tf       # Terraform + AzureRM version pins
├── providers.tf      # aliased providers, one per subscription
├── VM-SERVER01.tf    # SERVER01 — config block on top + all its resources (alias: connectivity)
├── VM-SERVER02.tf    # SERVER02 — ... (alias: management)
├── VM-SERVER03.tf    # SERVER03 — ... (alias: identity)
└── README.md
```

Each `VM-*.tf` is completely self-contained: a `locals` config block at the very top with the
only values you edit, then the VM's data lookups, Logic App, recurrence trigger, start action,
RBAC assignment, and outputs — all pinned to that VM's subscription via an explicit
`provider = azurerm.<alias>`.

## Subscriptions and provider aliases

Providers are defined once in `providers.tf`, one alias per subscription. There is no default
provider, so every resource/data source names its alias explicitly.

| VM | Subscription | Provider alias |
|---|---|---|
| SERVER01 | Connectivity | `azurerm.connectivity` |
| SERVER02 | Management | `azurerm.management` |
| SERVER03 | Identity | `azurerm.identity` |

Fill the real subscription IDs into `providers.tf`. The `subscription_id` in each VM's config
block is for reference only and must match the subscription of the alias that file uses.

## Schedules

Each VM has its own independent schedule, set in its config block. Times use `GMT Standard Time`,
which is UK local time and **observes British Summer Time automatically** (so 07:30 stays 07:30
on the clock year-round). Defaults in this repo:

| VM | Start | Days |
|---|---|---|
| SERVER01 | 07:30 | Mon–Fri |
| SERVER02 | 08:00 | Mon–Fri |
| SERVER03 | 06:45 | Mon–Fri |

To change a VM's time or days, edit only the `start_hour` / `start_minute` / `weekdays` /
`time_zone` values at the top of that VM's file and `terraform apply`.

## Prerequisites

- The VMs and their resource groups already exist (this repo never creates or modifies them).
- Terraform **>= 1.5.0**; AzureRM **~> 4.0** (installed by `terraform init`).
- A storage account + container for remote state (see `backend.tf`), or comment the backend
  block out to use local state.
- Rights to create a Logic App in each VM's resource group and to create a role assignment on
  each VM (`Microsoft.Authorization/roleAssignments/write`).
- Azure auth from the environment (`az login`, `ARM_*`, or workload/managed identity). No
  credentials live in the code.

## Deploy

```bash
az login

# 1) Put real subscription IDs in providers.tf and real state details in backend.tf.
# 2) Set the config block at the top of each VM-*.tf (vm_name, resource_group_name, schedule).

terraform init
terraform fmt -recursive
terraform validate
terraform plan
terraform apply
```

## Add another VM

1. Copy an existing file, e.g. `cp VM-SERVER01.tf VM-SERVER04.tf`.
2. In the new file, edit the config block at the top: `vm_name`, `resource_group_name`,
   `subscription_id`, and the schedule.
3. Find-and-replace the resource key `server01` → `server04` throughout the file (this renames
   every Terraform identifier and output so it doesn't collide with other files).
4. Update the provider alias on every `provider =` line to the VM's subscription, e.g.
   `azurerm.connectivity` → `azurerm.management` (there are 5 occurrences).
5. If the VM is in a brand-new subscription, add that aliased provider to `providers.tf`.
6. `terraform plan` then `terraform apply`.

No existing VM file changes, and no module is involved.

## Shared state — what to expect

All VMs share one state and one `plan`/`apply`:

- Editing, adding, or removing one VM affects only that VM's resources.
- A **runtime** failure on one VM does not roll back the others.
- A **plan-time** error on one VM (most often a `vm_name`/`resource_group_name` that doesn't
  exist) blocks the whole plan until you fix or remove that file. Work around it with
  `terraform apply -target=module` style targeting on the specific resources, e.g.
  `terraform apply -target=azurerm_logic_app_workflow.server01`.

This limitation is accepted by design. (True per-VM isolation would need a directory + state per
VM; this repo intentionally uses shared state.)

## Validate after apply

```bash
terraform output                         # all VMs' outputs

RG=RG-SERVERS; LA=la-SERVER01-autostart
az logic workflow show -g "$RG" -n "$LA" --query identity -o json
PID=$(az logic workflow show -g "$RG" -n "$LA" --query identity.principalId -o tsv)
az role assignment list --assignee "$PID" --scope \
  "$(az vm show -g "$RG" -n SERVER01 --query id -o tsv)" \
  --query "[].{role:roleDefinitionName, scope:scope}" -o table

az logic workflow trigger run -g "$RG" -n "$LA" --trigger-name Recurrence_Start
az vm get-instance-view -g "$RG" -n SERVER01 \
  --query "instanceView.statuses[?starts_with(code,'PowerState/')].displayStatus" -o tsv
```

## Security / least privilege

Each Logic App's managed identity gets **Virtual Machine Contributor** scoped to **its VM**
(not the resource group or subscription). For tighter privilege, swap the
`role_definition_name` for a custom role limited to
`Microsoft.Compute/virtualMachines/start/action` plus the required reads. No passwords, client
secrets, or keys appear anywhere.

## RBAC propagation

A new role assignment can take seconds (occasionally minutes) to propagate. If a VM's very first
run fires during that window it may fail; the next scheduled or manual run succeeds, and the
action's 4-attempt exponential retry absorbs brief delays. No artificial sleeps are used.

## Migration from the previous layout

The earlier version of this repo used a Terraform **module** with VMs `testvm` / `testvm2`
(Logic Apps `la-testvm` / `la-testvm2`) in local state. This new layout has different Terraform
addresses **and** different Azure resource names, so there is nothing to `state mv` cleanly — the
old resources simply drop out of the new configuration. To clean them up, pick one:

- **Before switching files** (if you still have the old config checked out): run
  `terraform destroy` with the old configuration to remove `la-testvm` / `la-testvm2` (the VMs
  themselves are data sources and are untouched).
- **After switching** (old config already replaced): delete the orphaned Logic Apps directly, e.g.
  ```bash
  az logic workflow delete -g baztest  -n la-testvm  --yes
  az logic workflow delete -g baztest2 -n la-testvm2 --yes
  ```
  and remove any leftover role assignments those identities held. The old local
  `terraform.tfstate` can then be archived/removed once you confirm nothing else is in it
  (`terraform state list` against the old config).

If instead you want to keep an already-deployed VM under the new scheme, note the Azure Logic App
name changes (`la-testvm` → `la-SERVER0x-autostart`), which forces a replacement regardless — so a
destroy-then-apply is the clean path.

## Optional: local state instead of remote

Comment out the `backend "azurerm"` block in `backend.tf` and run `terraform init`. State is then
kept locally. Not recommended for shared/team use.
