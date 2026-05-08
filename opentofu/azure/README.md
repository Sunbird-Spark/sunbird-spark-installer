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

| Resource | Purpose |
|----------|---------|
| AKS cluster | 2 × Standard_B16as_v2 nodes (16 vCPU / 64 GB RAM each) |
| Virtual Network | Dedicated VNet and subnet for AKS |
| Storage Account | Cloud storage for Sunbird content and backups |
| Key Vault | Secrets management |
| Managed Identity | Workload identity for AKS pods |
| OpenTofu state backend | Azure Storage container for Terraform state |

## global-values.yaml Reference

The main configuration file at `opentofu/azure/<env>/global-values.yaml` is filled in before running the installer. Key fields:

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

> Using Let's Encrypt? Set `global.lets_encrypt_ssl: true` and `global.cert_notifications.email`. Leave `proxy_private_key` and `proxy_certificate` blank.

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

This runbook supports any service that accepts a **webhook HTTP POST** with a JSON body:

| Service | How to get webhook URL |
|---------|----------------------|
| **Discord** | Channel Settings → Integrations → Webhooks → New Webhook |
| **Slack** | Apps → Incoming Webhooks → Add New Webhook |
| **Microsoft Teams** | Channel → Connectors → Incoming Webhook |
| **Google Chat** | Space Settings → Apps & Integrations → Webhooks |

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
