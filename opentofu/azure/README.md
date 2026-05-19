# Azure

Sunbird Spark deploys on Azure AKS. Infrastructure provisioning and application deployment are both handled by the installer — you do not need to create any Azure resources manually.

## Deployment Approaches

Two approaches are available, both covering infrastructure provisioning and deployment end-to-end:

**[private-repo-setup/README.md](../../private-repo-setup/README.md)**

| Approach | Description |
|----------|-------------|
| **GitHub Actions** | Automated CI/CD using OIDC federated credentials. Infra and deployments run from a private GitHub repository — no credentials stored in GitHub. |
| **Manual via Azure VM** | An Azure VM with a system-assigned managed identity runs `install.sh` directly over SSH. No CI/CD setup needed. |

## What Gets Provisioned

OpenTofu modules in `opentofu/azure/modules/` create:

---

#### Azure Infra Setup

## global-values.yaml Reference

```
  building_block: "" # building block name
  env: "" 
  environment: "" # use lowercase alphanumeric string between 1-9 characters
  domain: ""
  subscription_id: ""
  sunbird_cloud_storage_provider: azure 
  sunbird_google_captcha_site_key: 
  google_captcha_private_key: 
  sunbird_google_oauth_clientId: 
  sunbird_google_oauth_clientSecret: 
  mail_server_from_email: ""
  mail_server_password: ""
  mail_server_host: smtp.sendgrid.net
  mail_server_port: "587"
  mail_server_username: apikey
  sunbird_msg_91_auth: ""
  sunbird_msg_sender: ""
  youtube_apikey: ""
  proxy_private_key: |
   <private_key_generated_when_setting_up_ssl>
  proxy_certificate: |
   <certificate_generated_when_setting_up_ssl>
```
## AKS Kubernetes Version Upgrade

The AKS cluster is provisioned with a default Kubernetes version defined in `opentofu/azure/modules/aks/variables.tf`. AKS versions have a support lifecycle of approximately **12 months** after GA. When a version approaches end of life, you must upgrade to a supported version.

### When to Upgrade

AKS supports the **3 latest GA minor versions** at any time. Once your version falls outside this window, Microsoft may auto-upgrade your cluster. It is recommended to upgrade proactively before that happens.

Check the currently supported AKS versions at: https://learn.microsoft.com/en-us/azure/aks/supported-kubernetes-versions

### How to Upgrade

**Step 1 — Update the `aks_version` default in `opentofu/azure/modules/aks/variables.tf`:**
```hcl
variable "aks_version" {
  type        = string
  description = "AKS cluster version"
  default     = "<new-version>"  # e.g. "1.34.0"
}
```

**Step 2 — Apply via OpenTofu:**
```bash
cd opentofu/azure/aks
terragrunt plan
```
```
~ resource "azurerm_kubernetes_cluster" "aks" {
    ~ kubernetes_version = "1.33.0" -> "1.34.0"
}
Plan: 0 to add, 1 to change, 0 to destroy.
```

✅ **Safe to apply** — the plan shows `1 to change` with the version update.

❌ **Do NOT apply** if the plan shows `1 to destroy` — this means the cluster will be destroyed and recreated, causing downtime. Investigate before proceeding.

**Step 3 — If the plan shows `1 to change`, apply:**

```bash
terragrunt apply
```

> **❌ Do NOT apply** if the plan shows `1 to destroy` — this means the cluster will be destroyed and recreated, causing downtime. Investigate before proceeding.

**Step 3 — If the plan shows `1 to change`, apply:**

```bash
terragrunt apply
```

> **Note:** AKS only supports upgrading **one minor version at a time** (e.g., 1.33 → 1.34 → 1.35). You cannot skip versions.

### Upgrade Behavior: No Downtime Expected

When `aks_version` is updated, OpenTofu sends an in-place update to the AKS resource — **the cluster is not destroyed or recreated**. Azure performs a rolling upgrade:

1. **Control plane upgrades first** — the API server, etcd, and other control plane components are updated with no node disruption.
2. **Node pools upgrade in a rolling fashion** — Azure adds a temporary surge node (by default 1 extra node, or 33% of the pool), cordons and drains an old node, upgrades it, then moves on to the next.
3. **Workloads are rescheduled** — pods are gracefully evicted onto available nodes before each node is upgraded, so running workloads are preserved throughout.

| Field | Description |
|-------|-------------|
| `global.building_block` | Short prefix for all Azure resources (e.g. `"myorg"`). Lowercase letters only. |
| `global.env` | Short environment tag used inside the cluster (e.g. `"demo"`). |
| `global.environment` | 1–9 lowercase alphanumeric. Must match the `configs/` folder name. |
| `global.domain` | Your domain (e.g. `"sunbird.myorg.com"`). |
| `global.subscription_id` | Your Azure Subscription ID. |
| `global.cloud_storage_region` | Azure region (e.g. `"eastus"`, `"centralindia"`). |
| `global.proxy_private_key` | SSL/TLS private key in PEM format. |
| `global.proxy_certificate` | SSL/TLS certificate chain in PEM format (cert + CA bundle). |
| `global.aks_version` | Kubernetes version for the AKS cluster (e.g. `"1.35.1"`). **Always specify a version.** Check available versions with `az aks get-versions --location <region> --output table`. |

> Using Let's Encrypt? Set `global.lets_encrypt_ssl: true` and `global.cert_notifications.email`. Leave `proxy_private_key` and `proxy_certificate` blank.

## AKS Kubernetes Version

### Pinning the version

Set `global.aks_version` in `opentofu/azure/<env>/global-values.yaml` to lock the cluster to a specific Kubernetes release:

```yaml
global:
  aks_version: "1.35.1"   # always specify the exact Kubernetes version you want
```

Always set this to an explicit version. Leaving it unset risks Azure silently provisioning or re-applying a different version during maintenance, which can cause unexpected upgrades or downtime.

### Checking available versions

Before upgrading, list the versions available in your region:

```bash
az aks get-versions --location <your-region> --output table
```

Example output (truncated):

```
KubernetesVersion    Upgrades                                                                    Capabilities
-------------------  --------------------------------------------------------------------------  ---------------------------------------
1.35.3               None available                                                              KubernetesOfficial, AKSLongTermSupport
1.35.2               1.35.3                                                                      KubernetesOfficial, AKSLongTermSupport
1.35.1               1.35.2, 1.35.3                                                              KubernetesOfficial, AKSLongTermSupport
1.35.0               1.35.1, 1.35.2, 1.35.3                                                      KubernetesOfficial, AKSLongTermSupport
1.34.6               1.35.0, 1.35.1, 1.35.2, 1.35.3                                             KubernetesOfficial, AKSLongTermSupport
1.34.5               1.34.6, 1.35.0, 1.35.1, 1.35.2, 1.35.3                                     KubernetesOfficial, AKSLongTermSupport
1.34.4               1.34.5, 1.34.6, 1.35.0, 1.35.1, 1.35.2, 1.35.3                             KubernetesOfficial, AKSLongTermSupport
1.33.6               1.33.7, 1.33.8, 1.33.9, 1.33.10, 1.34.0, 1.34.1, 1.34.2, 1.34.3, 1.34.4   KubernetesOfficial, AKSLongTermSupport
```

The **Upgrades** column shows every version your current cluster can move to in a single operation. To reach a version that is not listed, you must upgrade in hops.

**Example — upgrading from `1.33.6` to `1.35.3`**

Looking at the `1.33.6` row, the highest available target is `1.34.4` — `1.35.x` does not appear. So a direct jump is not possible. The two-hop path is:

```
1.33.6  →  1.34.4  →  1.35.3
```

1. Set `aks_version: "1.34.4"` in `global-values.yaml` and apply.
2. Once the cluster is on `1.34.4`, set `aks_version: "1.35.3"` and apply again.

Always pick the **latest available patch** of the target minor version from the Upgrades list to get the most recent fixes in each hop.

### When to upgrade

| Trigger | Action |
|---------|--------|
| Azure announces end-of-support for your minor version (~12 months notice) | Plan an upgrade before the retirement date. |
| A CVE patch is released for your current minor version | Upgrade to the latest patch of the same minor (e.g. `1.34.3` → `1.34.7`). |
| A new minor version is required for a feature or dependency | Follow the incremental upgrade path below. |

### Step-by-step upgrade process

1. **Check available versions**

   ```bash
   az aks get-versions --location <your-region> --output table
   ```

   Identify the upgrade path. If you need to traverse multiple minor versions, plan each hop separately.

2. **Determine the next target version**

   Pick the version shown in the **Upgrades** column for your current version. If the final target is two or more minor versions away, start with the first intermediate version.

3. **Update `global-values.yaml`**

   Edit `opentofu/azure/<env>/global-values.yaml` (or the encrypted copy in your private repo):

   ```yaml
   global:
     aks_version: "1.34.4"   # set to next version in the upgrade path
   ```

4. **Apply the change**

   - **GitHub Actions**: commit the updated `global-values.yaml` and trigger the workflow (or push to the branch that runs it).  
   - **Manual / Azure VM**: run from the environment directory:

     ```bash
     cd opentofu/azure/<env>
     ./install.sh create_tf_resources
     ```

   OpenTofu will detect the version change, upgrade the AKS control plane, and then perform a rolling replacement of the worker nodes. This typically takes **25–35 minutes** per hop.

   > **Downtime warning:** Expect **25–35 minutes of service downtime** during the upgrade. AKS upgrades nodes by cordoning, draining, and replacing them one at a time (surge upgrade). During node replacement, pods are evicted and rescheduled — services will be unavailable until pods come back up on the new nodes.

5. **Verify the upgrade**

   ```bash
   kubectl version --short
   # or
   az aks show --resource-group <rg-name> --name <cluster-name> --query kubernetesVersion -o tsv
   ```

6. **Repeat for each hop** (if upgrading across multiple minor versions)

   Go back to step 3 with the next version in the path until you reach the final target.

# Azure Automation — AKS Auto Start/Stop Setup Guide

> Automatically start and stop AKS clusters on a schedule with holiday support, quota guard, and notifications.

---

## Overview

This setup uses **Azure Automation Account** with a **PowerShell runbook** to start and stop AKS clusters automatically on weekdays. It includes:

- Per-cluster schedules (Mon–Fri)
- Holiday skip for start schedules
- Quota guard (500 min/month free tier protection)
- Notifications for every event (Discord, Teams, Slack, or any webhook-based service)

---

## Architecture

```
Azure Automation Account
├── Runbook (PowerShell 7.2)
│   ├── Managed Identity Auth
│   ├── Holiday Check
│   ├── Quota Guard
│   └── Start / Stop AKS
├── Schedules (per cluster)
│   ├── Start — Mon-Fri at configured time IST
│   └── Stop  — Mon-Fri at configured time IST
└── Variables
    ├── HolidayDates
    ├── WebhookUrl
    └── QuotaLimitMinutes
```

---

## Prerequisites

- Azure Subscription
- AKS clusters already created
- A webhook-based notification service (Discord, Teams, Slack, etc.)
- Azure Portal access

---

## Step A — Create Automation Account

1. Go to **Azure Portal** → search `Automation Accounts` → **+ Create**
2. Fill in:
   - **Subscription** → the target subscription
   - **Resource Group** → the resource group
   - **Name** → e.g. `<company>-infra-startstop`
   - **Region** → same region as your AKS clusters
3. **Advanced** tab:
   - System assigned identity → **On**
4. **Networking** tab:
   - Connectivity → **Public access**
5. Add **Tags** as needed
6. Click **Review + Create** → **Create**

---

## Step B — Grant Roles to Managed Identity

For **each AKS cluster**:

1. Go to the AKS cluster → **Access control (IAM)**
2. Click **+ Add** → **Add role assignment**
3. Role = `Azure Kubernetes Service Contributor` → **Next**
4. Assign access to = **Managed identity**
5. Click **+ Select members** → select your Automation Account → **Select**
6. Click **Review + assign**

Also grant role on the **Automation Account itself**:
1. Go to Automation Account → **Access control (IAM)**
2. Same steps, Role = `Automation Contributor`
3. Assign to the same Managed Identity

---

## Step C — Create Automation Variables

Go to Automation Account → **Shared Resources** → **Variables** → **+ Add a variable**

| Name | Type | Encrypted | Value |
|------|------|-----------|-------|
| `HolidayDates` | String | No | JSON array of holiday dates |
| `WebhookUrl` | String | Yes | Your notification webhook URL |
| `QuotaLimitMinutes` | Integer | No | `450` |

### HolidayDates Format
```json
["2026-01-01","2026-01-26","2026-08-15","2026-10-02","2026-12-25"]
```
> Update this list every year with company public holidays. Only include weekday holidays — weekend holidays are automatically skipped by the schedule.

### QuotaLimitMinutes
Set to `450` (out of 500 free minutes/month). This gives a 50-minute buffer before hitting Azure's free tier limit.

---

## Step D — Notification Webhook Setup

This runbook currently posts a **Discord-style webhook HTTP POST** JSON payload using the `content` field, so it supports **Discord or other Discord-compatible webhooks**.

| Service | How to get webhook URL |
|---------|----------------------|
| **Discord** | Channel Settings → Integrations → Webhooks → New Webhook |

> If you want to use Slack, Microsoft Teams, or Google Chat, you must first update the runbook payload format to match that service's schema (for example, `text` for Slack/Google Chat or a Teams message card/adaptive card payload).

Once you have the webhook URL:
1. Go to Automation Account → **Variables** → `WebhookUrl`
2. Paste the URL → set **Encrypted = Yes**

> Never share or hardcode the webhook URL — always store it as an encrypted variable.

---

## Step E — Create & Publish Runbook

1. Automation Account → **Runbooks** → **+ Create a runbook**

| Field | Value |
|-------|-------|
| Name | `aks-startstop` |
| Runbook type | `PowerShell` |
| Runtime version | `7.2` |
| Description | `Auto start and stop AKS clusters based on schedule and holiday calendar` |

2. Click **Create** → **Edit in portal**
3. Paste the PowerShell script below
4. Click **Save** → **Publish**

---

## PowerShell Runbook Script

```powershell
param (
    [Parameter(Mandatory = $true)]
    [string]$Action,         # "Start" or "Stop"
    [Parameter(Mandatory = $true)]
    [string]$ClusterName,    # AKS cluster name
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroup   # AKS cluster resource group
)

# -----------------------------------------------
# Update these values for your environment
# -----------------------------------------------
$subscriptionId          = "YOUR_SUBSCRIPTION_ID"
$automationResourceGroup = "YOUR_AUTOMATION_ACCOUNT_RESOURCE_GROUP"
$automationAccountName   = "YOUR_AUTOMATION_ACCOUNT_NAME"
# -----------------------------------------------

# Connect using Managed Identity
Write-Output "Connecting to Azure using Managed Identity..."
Connect-AzAccount -Identity
Set-AzContext -SubscriptionId $subscriptionId
Write-Output "Connected successfully."

# IST Time
$istTime = (Get-Date).ToUniversalTime().AddHours(5.5).ToString('dd-MM-yyyy HH:mm')

# Notification Function (supports Discord, Slack, Teams, or any webhook)
function Send-Notification {
    param([string]$Message)
    try {
        Write-Output "Sending notification..."
        $webhookUrl = Get-AutomationVariable -Name "WebhookUrl"
        $body = @{ content = $Message } | ConvertTo-Json
        Invoke-RestMethod -Uri $webhookUrl -Method Post -Body $body -ContentType "application/json"
        Write-Output "Notification sent successfully."
    } catch {
        Write-Output "Notification failed: $_"
    }
}

# Holiday Check (only for Start)
if ($Action -eq "Start") {
    Write-Output "Checking holiday list..."
    $holidayDates = Get-AutomationVariable -Name "HolidayDates"
    $holidays = $holidayDates | ConvertFrom-Json
    $today = (Get-Date).ToUniversalTime().AddHours(5.5).ToString("yyyy-MM-dd")
    Write-Output "Today is: $today"

    if ($holidays -contains $today) {
        Write-Output "Today is a holiday. Skipping start."
        Send-Notification "[HOLIDAY] Today ($today) is a holiday - Skipping START for AKS cluster: $ClusterName"
        exit
    } else {
        Write-Output "Not a holiday. Proceeding..."
    }
}

# Quota Guard
Write-Output "Checking quota usage..."
try {
    $quotaLimit = Get-AutomationVariable -Name "QuotaLimitMinutes"
    Write-Output "Quota limit set to: $quotaLimit minutes"
    $usageUrl = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$automationResourceGroup/providers/Microsoft.Automation/automationAccounts/$automationAccountName/usages?api-version=2023-11-01"
    $token = (Get-AzAccessToken).Token
    $headers = @{ Authorization = "Bearer $token" }
    $usage = Invoke-RestMethod -Uri $usageUrl -Headers $headers -Method Get
    $usedMinutes = ($usage.value | Where-Object { $_.name.value -eq "AccountUsage" }).currentValue
    Write-Output "Minutes used this month: $usedMinutes"

    if ($usedMinutes -ge $quotaLimit) {
        Write-Output "Quota limit reached! Skipping $Action."
        Send-Notification "[WARNING] Quota limit reached ($usedMinutes min used out of 500) - Skipping $Action for AKS cluster: $ClusterName"
        exit
    } else {
        Write-Output "Quota OK. Proceeding..."
    }
} catch {
    Write-Output "Quota check failed, proceeding anyway: $_"
}

# Start or Stop AKS
if ($Action -eq "Start") {
    Write-Output "Starting AKS cluster: $ClusterName"
    Start-AzAksCluster -ResourceGroupName $ResourceGroup -Name $ClusterName
    Write-Output "AKS cluster $ClusterName started successfully."
    Send-Notification "[START] AKS cluster $ClusterName started successfully at $istTime IST"
} elseif ($Action -eq "Stop") {
    Write-Output "Stopping AKS cluster: $ClusterName"
    Stop-AzAksCluster -ResourceGroupName $ResourceGroup -Name $ClusterName
    Write-Output "AKS cluster $ClusterName stopped successfully."
    Send-Notification "[STOP] AKS cluster $ClusterName stopped successfully at $istTime IST"
} else {
    Write-Output "Invalid action: $Action. Use 'Start' or 'Stop'."
    Send-Notification "[ERROR] Invalid action: $Action for AKS cluster: $ClusterName"
}
```

> Replace `YOUR_SUBSCRIPTION_ID`, `YOUR_AUTOMATION_ACCOUNT_RESOURCE_GROUP`, and `YOUR_AUTOMATION_ACCOUNT_NAME` with the actual values before publishing.

---

## Step F — Create Schedules

Go to Automation Account → **Schedules** → **+ Add a schedule** for each cluster.

Create **one Start + one Stop schedule per cluster**:

| Name | Description | Time | Recurrence | Days |
|------|-------------|------|------------|------|
| `sched-<cluster>-start-<time>` | Start cluster at HH:MM IST | HH:MM in 24hr format | Weekly | Mon-Fri |
| `sched-<cluster>-stop-<time>` | Stop cluster at HH:MM IST | HH:MM in 24hr format | Weekly | Mon-Fri |

**Schedule settings:**
- Time zone = `India Standard Time` (or the local timezone)
- Recur every = `1 Week`
- Set expiration = `No`

---

## Step G — Link Schedules to Runbook

1. Go to `aks-startstop` runbook → **Schedules** → **+ Add a schedule**
2. Select the schedule
3. Click **Configure parameters and run settings**
4. Fill parameters:

| Parameter | Value |
|-----------|-------|
| `Action` | `Start` or `Stop` |
| `ClusterName` | the AKS cluster name |
| `ResourceGroup` | cluster's resource group name |

5. Click **OK** → **Create**

> Repeat for each schedule. Each schedule passes its own cluster details — one runbook handles all clusters.

---

## Notifications

Supports any webhook-based service — Discord, Slack, Microsoft Teams, Google Chat, or any custom endpoint.

| Event | Message |
|-------|---------|
| Cluster started | `[START] AKS cluster <name> started successfully at <time> IST` |
| Cluster stopped | `[STOP] AKS cluster <name> stopped successfully at <time> IST` |
| Holiday skip | `[HOLIDAY] Today (<date>) is a holiday - Skipping START for AKS cluster: <name>` |
| Quota warning | `[WARNING] Quota limit reached (<X> min used out of 500) - Skipping <action>` |
| Error | `[ERROR] Invalid action: <action> for AKS cluster: <name>` |

---

## Weekend & Holiday Behaviour

| Day | Start | Stop |
|-----|-------|------|
| Monday–Friday | Runs at scheduled time | Runs at scheduled time |
| Saturday–Sunday | Never runs (not in schedule) | Never runs |
| Public Holiday | Skipped — notification sent | Always runs |

---

## Quota Guard

- Azure Automation free tier = **500 min/month**
- `QuotaLimitMinutes` default = `450` — 50 min safety buffer
- If usage >= limit → runbook skips action → notification sent
- Resets automatically every month

---

## Testing

### Test Start/Stop manually
1. Go to `aks-startstop` runbook → **Start**
2. Pass parameters: `Action=Start`, `ClusterName=<name>`, `ResourceGroup=<rg>`
3. Check **Jobs** → **Output** for step-by-step logs
4. Check notification channel

### Test Holiday
1. Add today's date to `HolidayDates` variable
2. Run manually with `Action=Start`
3. Verify cluster does NOT start and `[HOLIDAY]` notification is received
4. Remove today's date from variable after testing

### Test Quota Guard
1. Set `QuotaLimitMinutes` to `1`
2. Run manually
3. Verify cluster does NOT start and `[WARNING]` notification is received
4. Set `QuotaLimitMinutes` back to `450`

---

## Operations

### Add a new cluster
1. Grant `Azure Kubernetes Service Contributor` role to Automation Account managed identity on the new cluster
2. Create 2 new schedules (start + stop)
3. Link schedules to `aks-startstop` runbook with new cluster parameters

### Update holiday list
Go to Automation Account → **Variables** → `HolidayDates` → **Edit** → update JSON array

### Unplanned holiday
Add today's date to `HolidayDates` variable — takes effect immediately on next scheduled run

### Disable a schedule temporarily
Go to `aks-startstop` runbook → **Schedules** → find the schedule → **Disable**

### Re-enable a schedule
Go to `aks-startstop` runbook → **Schedules** → find the schedule → **Enable**

---

## Cost Summary

| Resource | Cost |
|----------|------|
| Azure Automation (up to 500 min/month) | Free |
| Webhook notifications (Discord/Slack/Teams) | Free |
| Azure outbound network | Free |
| **Total** | **Free** |
