# Understanding Azure Managed Identity Migration - Beginner's Guide

## Table of Contents
1. [What Problem Are We Solving?](#what-problem-are-we-solving)
2. [Understanding Azure Workload Identity](#understanding-azure-workload-identity)
3. [Repository Workflow Overview](#repository-workflow-overview)
4. [Detailed Explanation of Changes](#detailed-explanation-of-changes)
5. [Complete Flow Diagram](#complete-flow-diagram)
6. [FAQ - Your Specific Questions](#faq---your-specific-questions)

---

## What Problem Are We Solving?

### The Old Way (Security Risk)

Before this change, the content service accessed Azure Blob Storage using **storage account keys**:

```yaml
# ConfigMap had these values:
AZURE_STORAGE_ACCOUNT: "mystorageaccount"
AZURE_STORAGE_KEY: "super-secret-key-12345..."  # ❌ Security Risk!
```

**Problems**:
- 🔴 Storage keys are like passwords - if someone gets them, they can access your storage
- 🔴 Keys stored in ConfigMaps can be read by anyone with Kubernetes access
- 🔴 Keys never expire unless you manually rotate them
- 🔴 If keys leak, you have to regenerate them and update all applications

### The New Way (Secure)

Now, we use **Azure Managed Identity** with **Workload Identity**:

```yaml
# ServiceAccount has this annotation:
azure.workload.identity/client-id: "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
```

**Benefits**:
- ✅ No passwords/keys stored anywhere
- ✅ Automatic token rotation (every hour)
- ✅ Tokens are temporary and expire automatically
- ✅ Azure handles all the security

---

## Understanding Azure Workload Identity

### What is a Managed Identity?

Think of a **Managed Identity** as a special Azure account that represents your application. Instead of using passwords, Azure knows this account belongs to your application.

```
Traditional Login:
Username: myapp
Password: super-secret-123  ❌

Managed Identity:
Identity: knowledgebb-dev-content-service-mi
Password: (Azure handles this automatically) ✅
```

### What is Workload Identity?

**Workload Identity** is the bridge between Kubernetes and Azure. It allows your Kubernetes pods to use Azure Managed Identity.

**How it works** (simplified):

```
1. Pod starts with a Kubernetes ServiceAccount
2. Kubernetes gives the pod a token (like a temporary ID card)
3. Pod shows this token to Azure
4. Azure checks: "Is this token linked to a Managed Identity?"
5. If yes, Azure gives the pod access to storage
```

### What is OIDC?

**OIDC** (OpenID Connect) is the technology that makes this token exchange work.

Think of it like this:
- **Kubernetes** is like your school
- **Azure** is like a library
- **OIDC** is the agreement between school and library that says: "If a student shows a valid school ID, give them library access"

When we enable `oidc_issuer_enabled = true`, we're telling Azure: "Trust the IDs (tokens) that this Kubernetes cluster issues."

---

## Repository Workflow Overview

### Understanding the Terraform Directory Structure

The `terraform/azure` directory has **three main directories** that work together. Understanding these is key to working with this repository.

```
terraform/azure/
├── modules/           # Reusable Terraform code (the "what")
├── _common/           # Shared configuration (the "how")
└── template/          # Environment templates (the "where")
```

Let me explain each one with real examples:

---

### 1. `modules/` - The Reusable Building Blocks

**What it is**: Contains the actual Terraform code that creates Azure resources.

**Think of it as**: A library of blueprints. Each module is a blueprint for creating a specific type of infrastructure.

**Example Structure**:
```
modules/
├── aks/                          # Blueprint for Kubernetes cluster
│   ├── main.tf                   # Creates AKS cluster
│   ├── variables.tf              # What inputs it needs
│   └── outputs.tf                # What values it returns
│
├── storage/                      # Blueprint for storage account
│   ├── main.tf                   # Creates storage account
│   ├── variables.tf              # What inputs it needs
│   └── outputs.tf                # What values it returns
│
└── content-service-identity/     # Blueprint for managed identity
    ├── main.tf                   # Creates managed identity
    ├── variables.tf              # What inputs it needs
    └── outputs.tf                # What values it returns
```

**Real Example** - `modules/aks/main.tf`:
```hcl
# This is the blueprint - it doesn't have actual values
resource "azurerm_kubernetes_cluster" "aks" {
  name                = var.cluster_name        # ← Variable, not hardcoded
  location            = var.location            # ← Variable, not hardcoded
  resource_group_name = var.resource_group_name # ← Variable, not hardcoded
  
  # ... rest of configuration ...
}
```

**Key Point**: Modules are **generic and reusable**. They don't know if they're creating dev, staging, or prod resources.

---

### 2. `_common/` - The Shared Configuration

**What it is**: Contains Terragrunt configuration that tells **how to use the modules**.

**Think of it as**: The instruction manual for each blueprint. It says "use this module, with these dependencies, and these inputs."

**Example Structure**:
```
_common/
├── aks.hcl                       # How to use the AKS module
├── storage.hcl                   # How to use the storage module
├── content-service-identity.hcl  # How to use the identity module
└── output-file.hcl               # How to use the output-file module
```

**Real Example** - `_common/aks.hcl`:
```hcl
locals {
  # Read values from global-values.yaml
  global_vars     = yamldecode(file(find_in_parent_folders("global-values.yaml")))
  environment     = local.global_vars.global.environment
  building_block  = local.global_vars.global.building_block
  location        = local.global_vars.global.cloud_storage_region
}

terraform {
  source = "../../modules//aks/"  # ← Use the AKS module
}

dependency "network" {
  config_path = "../network"      # ← Depends on network module
}

inputs = {
  # Pass values to the module
  environment         = local.environment
  building_block      = local.building_block
  resource_group_name = dependency.network.outputs.resource_group_name
  location            = local.location
}
```

**Key Point**: `_common/` files are **shared across all environments**. They define the logic once, used everywhere.

---

### 3. `template/` - The Environment Templates

**What it is**: Contains minimal files that **include the common configuration** for each environment.

**Think of it as**: A shortcut that says "use the common configuration for this module."

**Example Structure**:
```
template/
├── aks/
│   └── terragrunt.hcl            # Includes _common/aks.hcl
├── storage/
│   └── terragrunt.hcl            # Includes _common/storage.hcl
└── content-service-identity/
    └── terragrunt.hcl            # Includes _common/content-service-identity.hcl
```

**Real Example** - `template/aks/terragrunt.hcl`:
```hcl
include "root" {
  path = find_in_parent_folders("terragrunt.hcl")
}

include "environment" {
  path = "${get_terragrunt_dir()}/../../_common/aks.hcl"  # ← Include common config
}
```

**That's it!** Just 7 lines that say "use the common AKS configuration."

**Key Point**: Templates are **copied to each environment** (dev, staging, prod). They're identical across environments.

---

### How They Work Together

Let's trace through a complete example of creating an AKS cluster in the **dev** environment:

#### Step 1: Copy Template to Environment

When you create a new environment (e.g., `dev`), you copy the template:

```bash
# Copy the template to create dev environment
cp -r template/ dev/
```

Result:
```
terraform/azure/
├── dev/                          # ← New environment
│   ├── aks/
│   │   └── terragrunt.hcl        # ← Copied from template
│   ├── storage/
│   │   └── terragrunt.hcl
│   └── global-values.yaml        # ← Environment-specific values
```

#### Step 2: Set Environment-Specific Values

Edit `dev/global-values.yaml`:
```yaml
global:
  environment: "dev"
  building_block: "knowledgebb"
  cloud_storage_region: "East US"
  subscription_id: "12345678-1234-1234-1234-123456789012"
```

#### Step 3: Run Terragrunt

```bash
cd terraform/azure/dev/aks
terragrunt apply
```

#### Step 4: The Magic Happens

```
1. terragrunt.hcl (in dev/aks/)
   ↓ includes
   
2. _common/aks.hcl
   ↓ reads global-values.yaml
   ↓ gets: environment="dev", location="East US"
   ↓ points to
   
3. modules/aks/
   ↓ receives inputs
   ↓ creates AKS cluster with name "knowledgebb-dev"
```

---

### Complete Example: Creating Resources in 3 Environments

Let's say you want to deploy to **dev**, **staging**, and **prod**:

```
terraform/azure/
├── modules/                      # ← Write once
│   └── aks/
│       └── main.tf               # Generic AKS blueprint
│
├── _common/                      # ← Configure once
│   └── aks.hcl                   # How to use AKS module
│
├── template/                     # ← Template once
│   └── aks/
│       └── terragrunt.hcl        # Include common config
│
├── dev/                          # ← Environment 1
│   ├── aks/
│   │   └── terragrunt.hcl        # (copied from template)
│   └── global-values.yaml
│       environment: "dev"
│       cloud_storage_region: "East US"
│
├── staging/                      # ← Environment 2
│   ├── aks/
│   │   └── terragrunt.hcl        # (copied from template)
│   └── global-values.yaml
│       environment: "staging"
│       cloud_storage_region: "West US"
│
└── prod/                         # ← Environment 3
    ├── aks/
    │   └── terragrunt.hcl        # (copied from template)
    └── global-values.yaml
        environment: "prod"
        cloud_storage_region: "Central US"
```

**Result**:
- **Dev**: Creates `knowledgebb-dev` AKS cluster in East US
- **Staging**: Creates `knowledgebb-staging` AKS cluster in West US
- **Prod**: Creates `knowledgebb-prod` AKS cluster in Central US

**All using**:
- Same module code (modules/aks/)
- Same configuration logic (_common/aks.hcl)
- Same template (template/aks/terragrunt.hcl)
- Different values (each environment's global-values.yaml)

---

### Why This Structure?

#### ❌ Without This Structure (Bad)

```
dev/aks/terragrunt.hcl           (100 lines of config)
staging/aks/terragrunt.hcl       (100 lines of config - DUPLICATE!)
prod/aks/terragrunt.hcl          (100 lines of config - DUPLICATE!)
```

**Problems**:
- Need to update 3 files to change one thing
- Easy to make mistakes
- Hard to keep environments consistent

#### ✅ With This Structure (Good)

```
_common/aks.hcl                  (100 lines - SHARED)
template/aks/terragrunt.hcl      (7 lines - includes common)
dev/aks/terragrunt.hcl           (7 lines - copy of template)
staging/aks/terragrunt.hcl       (7 lines - copy of template)
prod/aks/terragrunt.hcl          (7 lines - copy of template)
```

**Benefits**:
- Update once in `_common/`, applies to all environments
- Minimal code duplication
- Environments stay consistent

---

### Real-World Workflow

#### Scenario: You need to add a new module for "database"

**Step 1**: Create the module
```bash
# Create the blueprint
mkdir -p modules/database
# Write main.tf, variables.tf, outputs.tf
```

**Step 2**: Create common configuration
```bash
# Create the configuration
# Write _common/database.hcl
```

**Step 3**: Create template
```bash
# Create the template
mkdir -p template/database
# Write template/database/terragrunt.hcl (7 lines)
```

**Step 4**: Deploy to environments
```bash
# Copy template to dev
cp -r template/database dev/

# Deploy
cd dev/database
terragrunt apply

# Repeat for staging and prod
```

---

### Summary Table

| Directory | Purpose | Contains | Reusable? | Example |
|-----------|---------|----------|-----------|---------|
| **modules/** | Terraform code | `main.tf`, `variables.tf`, `outputs.tf` | ✅ Yes - across all environments | `modules/aks/main.tf` |
| **_common/** | Configuration logic | Terragrunt `.hcl` files with dependencies and inputs | ✅ Yes - across all environments | `_common/aks.hcl` |
| **template/** | Environment template | Minimal `.hcl` files that include common config | ✅ Yes - copied to each environment | `template/aks/terragrunt.hcl` |
| **dev/**, **staging/**, **prod/** | Actual environments | Copy of template + `global-values.yaml` | ❌ No - specific to each environment | `dev/aks/terragrunt.hcl` |

---

### Key Takeaways

1. **modules/** = The "what" (Terraform code that creates resources)
2. **_common/** = The "how" (Configuration that uses the modules)
3. **template/** = The "where" (Template to copy for new environments)

4. **Write once, use everywhere**:
   - Module code: Write once in `modules/`
   - Configuration: Write once in `_common/`
   - Template: Write once in `template/`
   - Deploy: Copy template to each environment

5. **Environment-specific values** go in `global-values.yaml` in each environment directory

---

### How This Repository is Organized

```
sunbird-spark-installer/
├── terraform/              # Infrastructure as Code
│   └── azure/
│       ├── modules/        # Reusable Terraform components
│       ├── _common/        # Shared configuration
│       └── template/       # Templates for new environments
│
└── helmcharts/            # Application deployment
    └── knowledgebb/
        └── charts/
            └── knowlg/    # Content service
```

### The Workflow

**Step 1: Terraform Creates Infrastructure**
```
terraform/azure/<environment>/
├── network/          → Creates VPC, subnets
├── aks/              → Creates Kubernetes cluster
├── storage/          → Creates storage account
├── content-service-identity/  → Creates managed identity (NEW!)
└── output-file/      → Generates configuration files
```

**Step 2: Helm Deploys Applications**
```
helmcharts/knowledgebb/
└── Uses configuration from Terraform
    └── Deploys content service with managed identity
```

### Why This Separation?

- **Terraform** = Infrastructure (things that rarely change)
  - Azure resources
  - Networking
  - Storage accounts
  
- **Helm** = Applications (things that change frequently)
  - Application deployments
  - Configuration updates
  - Scaling

---

## Detailed Explanation of Changes

### Change 1: Enable OIDC on AKS

**File**: `terraform/azure/modules/aks/main.tf`

```hcl
resource "azurerm_kubernetes_cluster" "aks" {
  # ... other config ...
  
  oidc_issuer_enabled       = true
  workload_identity_enabled = true
}
```

**Why do we need `oidc_issuer_enabled = true`?**

This enables the "trust agreement" between Kubernetes and Azure.

**What happens when enabled**:
1. AKS creates a special URL called "OIDC Issuer URL"
2. This URL is like a "certificate authority" for your cluster
3. Azure can verify tokens from your cluster using this URL

**Real-world analogy**:
- Without OIDC: Azure doesn't trust any Kubernetes tokens
- With OIDC: Azure says "I trust tokens from this specific Kubernetes cluster"

**The OIDC Issuer URL looks like**:
```
https://eastus.oic.prod-aks.azure.com/12345678-1234-1234-1234-123456789012/abcdef/
```

This URL is unique to your cluster and is used to verify tokens.

---

### Change 2: Add AKS Outputs

**File**: `terraform/azure/modules/aks/outputs.tf`

```hcl
output "oidc_issuer_url" {
  value = azurerm_kubernetes_cluster.aks.oidc_issuer_url
}

output "resource_group_name" {
  value = var.resource_group_name
}

output "location" {
  value = var.location
}
```

**Why do we need to fetch these values separately?**

Great question! Here's why:

**1. OIDC Issuer URL**
- This is **generated by Azure** when the cluster is created
- We don't know it beforehand
- We need it to create the federated credential

**2. Resource Group Name and Location**
- Yes, we used these to create the cluster
- But Terraform modules are **isolated** - they don't automatically share variables
- The `content-service-identity` module needs these values
- Instead of hardcoding them again, we **output** them from the AKS module and **input** them to the identity module

**Why not hardcode?**

```hcl
# ❌ Bad - Hardcoded
resource "azurerm_user_assigned_identity" "content_service" {
  resource_group_name = "knowledgebb-dev-rg"  # What if this changes?
  location = "East US"                         # What if we deploy to another region?
}

# ✅ Good - Dynamic
resource "azurerm_user_assigned_identity" "content_service" {
  resource_group_name = var.resource_group_name  # Gets value from AKS module
  location = var.location                         # Gets value from AKS module
}
```

**The Flow**:
```
AKS Module
  ↓ outputs: resource_group_name, location, oidc_issuer_url
  ↓
Content-Service-Identity Module
  ↓ uses these values to create managed identity
```

---

### Change 3: Create Content Service Identity Module

**What does this module do?**

This module creates **3 Azure resources**:

#### Resource 1: Managed Identity

```hcl
resource "azurerm_user_assigned_identity" "content_service" {
  name = "knowledgebb-dev-content-service-mi"
  resource_group_name = var.resource_group_name
  location = var.location
}
```

**What it does**: Creates a special Azure identity for the content service

**Think of it as**: Creating a user account in Azure specifically for your application

**Output**: A Client ID (like a username): `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`

#### Resource 2: Role Assignment

```hcl
resource "azurerm_role_assignment" "content_service_storage" {
  scope = var.storage_account_id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id = azurerm_user_assigned_identity.content_service.principal_id
}
```

**What it does**: Gives the managed identity permission to access storage

**Think of it as**: Giving your application account the key to the storage room

**Permissions granted**:
- Read files from storage
- Write files to storage
- Delete files from storage
- List files in storage

#### Resource 3: Federated Identity Credential

```hcl
resource "azurerm_federated_identity_credential" "content_service" {
  name = "knowledgebb-dev-content-service-federated-credential"
  parent_id = azurerm_user_assigned_identity.content_service.id
  issuer = var.oidc_issuer_url
  subject = "system:serviceaccount:sunbird:content-service-sa"
  audience = ["api://AzureADTokenExchange"]
}
```

**What it does**: Creates the link between Kubernetes and Azure

**Think of it as**: Telling Azure "If someone shows you a token from Kubernetes ServiceAccount 'content-service-sa', trust them as this managed identity"

**Breaking down the fields**:
- `issuer`: The OIDC URL from your Kubernetes cluster (proves the token is from your cluster)
- `subject`: The specific Kubernetes ServiceAccount name (proves which pod/app it is)
- `audience`: Always `api://AzureADTokenExchange` (Azure's token exchange service)

---

### Change 4: Update Global Values Template

**File**: `terraform/azure/modules/output-file/global-cloud-values.yaml.tfpl`

```yaml
global:
  # ... other values ...
  
  # NEW: Managed Identity Configuration
  content_service_client_id: ${content_service_client_id}
  content_service_sa_name: ${content_service_sa_name}
```

**How will these variables be used?**

These values flow from Terraform to Helm:

**1. `content_service_client_id`**

**Where it comes from**: Terraform outputs this from the managed identity

**Where it goes**: Helm uses it in the ServiceAccount annotation

**Flow**:
```
Terraform creates managed identity
  ↓ outputs client_id: "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
  ↓
Output-file module writes to global-cloud-values.yaml
  ↓
Helm reads global-cloud-values.yaml
  ↓
ServiceAccount gets annotation:
  azure.workload.identity/client-id: "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
```

**2. `content_service_sa_name`**

**Where it comes from**: Static value `"content-service-sa"`

**Where it goes**: 
- Helm uses it to create the ServiceAccount with this name
- Deployment uses it to reference the ServiceAccount

**Why static?**: The name must match what's in the federated credential, so we use the same name everywhere.

---

### Change 5: Update Helm Chart

**File**: `helmcharts/knowledgebb/charts/knowlg/values.yaml`

```yaml
serviceAccount:
  create: true
  name: "content-service-sa"
```

**Why do we need to explicitly specify the ServiceAccount name?**

Excellent question! Here's why the name `"content-service-sa"` is important:

**Reason 1: Federated Credential Match**

The federated credential in Azure has this subject:
```
system:serviceaccount:sunbird:content-service-sa
                                 ↑
                        This must match exactly!
```

If the ServiceAccount has a different name, Azure won't trust it.

**Reason 2: Consistency**

Without explicit naming, Helm would generate a name like:
```
knowlg-knowledgebb-dev  ❌ (doesn't match federated credential)
```

With explicit naming:
```
content-service-sa  ✅ (matches federated credential)
```

**Reason 3: Multiple Environments**

The same name works across all environments:
- Dev: `content-service-sa`
- Staging: `content-service-sa`
- Prod: `content-service-sa`

Only the **managed identity** changes per environment:
- Dev: `knowledgebb-dev-content-service-mi`
- Staging: `knowledgebb-staging-content-service-mi`
- Prod: `knowledgebb-prod-content-service-mi`

---

### Change 6: Content-Service-Identity Template

**File**: `terraform/azure/template/content-service-identity/terragrunt.hcl`

```hcl
include "root" {
  path = find_in_parent_folders("terragrunt.hcl")
}

include "environment" {
  path = "${get_terragrunt_dir()}/../../_common/content-service-identity.hcl"
}
```

**Why do we need this template?**

This is part of the Terragrunt pattern used in this repository. Let me explain:

**The Problem**: You have multiple environments (dev, staging, prod) that need the same infrastructure with different values.

**Without Templates**:
```
terraform/azure/dev/content-service-identity/
  └── terragrunt.hcl  (100 lines of config)

terraform/azure/staging/content-service-identity/
  └── terragrunt.hcl  (100 lines of config - DUPLICATE!)

terraform/azure/prod/content-service-identity/
  └── terragrunt.hcl  (100 lines of config - DUPLICATE!)
```

**With Templates**:
```
terraform/azure/_common/
  └── content-service-identity.hcl  (100 lines - SHARED)

terraform/azure/template/content-service-identity/
  └── terragrunt.hcl  (7 lines - includes common config)

terraform/azure/dev/content-service-identity/
  └── terragrunt.hcl  (7 lines - includes template)

terraform/azure/staging/content-service-identity/
  └── terragrunt.hcl  (7 lines - includes template)
```

**How it works**:

1. **`_common/content-service-identity.hcl`**: Contains all the logic (dependencies, inputs, etc.)
2. **`template/content-service-identity/terragrunt.hcl`**: Includes the common config
3. **`<env>/content-service-identity/terragrunt.hcl`**: Just copies the template

**Benefits**:
- ✅ Write configuration once, use everywhere
- ✅ Changes to common config apply to all environments
- ✅ Less duplication, fewer errors

---

## Complete Flow Diagram

### End-to-End Flow

```
┌─────────────────────────────────────────────────────────────────┐
│ STEP 1: Terraform Creates Infrastructure                        │
└─────────────────────────────────────────────────────────────────┘

1. Create AKS Cluster (with OIDC enabled)
   ↓
   Outputs: oidc_issuer_url = "https://eastus.oic.prod-aks.azure.com/..."

2. Create Managed Identity
   ↓
   Creates: knowledgebb-dev-content-service-mi
   Outputs: client_id = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"

3. Create Role Assignment
   ↓
   Grants: "Storage Blob Data Contributor" to managed identity

4. Create Federated Credential
   ↓
   Links: Kubernetes SA "content-service-sa" → Managed Identity

5. Generate Global Values
   ↓
   Writes: content_service_client_id to global-cloud-values.yaml

┌─────────────────────────────────────────────────────────────────┐
│ STEP 2: Helm Deploys Application                                │
└─────────────────────────────────────────────────────────────────┘

6. Create ServiceAccount
   ↓
   Name: content-service-sa
   Annotation: azure.workload.identity/client-id = "xxxxxxxx..."

7. Create Deployment
   ↓
   Uses: serviceAccountName = content-service-sa
   Env: AZURE_CLIENT_ID = "xxxxxxxx..."

┌─────────────────────────────────────────────────────────────────┐
│ STEP 3: Runtime - Token Exchange                                │
└─────────────────────────────────────────────────────────────────┘

8. Pod Starts
   ↓
   Kubernetes assigns ServiceAccount "content-service-sa"

9. Workload Identity Webhook Injects Tokens
   ↓
   Adds: AZURE_FEDERATED_TOKEN_FILE = "/var/run/secrets/azure/tokens/..."
   Mounts: Kubernetes token as a file

10. Application Needs Storage Access
    ↓
    Azure SDK reads AZURE_CLIENT_ID and AZURE_FEDERATED_TOKEN_FILE

11. Token Exchange
    ↓
    SDK sends Kubernetes token to Azure AD
    Azure AD checks federated credential
    Azure AD verifies: "Is this token from the right cluster and SA?"

12. Azure AD Issues Access Token
    ↓
    Gives: Temporary Azure AD token (valid for 1 hour)

13. Application Accesses Storage
    ↓
    Uses: Azure AD token to authenticate
    RBAC: Checks "Storage Blob Data Contributor" permission
    Success: Application can read/write blobs
```

---

## FAQ - Your Specific Questions

### Q1: Why `oidc_issuer_enabled = true`?

**Answer**: This enables the trust mechanism between Kubernetes and Azure.

**Without OIDC**:
- Kubernetes tokens are meaningless to Azure
- Azure has no way to verify if a token is legitimate

**With OIDC**:
- Kubernetes publishes a public key at the OIDC issuer URL
- Azure can verify tokens using this public key
- Azure knows: "This token definitely came from this specific Kubernetes cluster"

**Analogy**: 
- OIDC is like a school's official stamp on student IDs
- Without it, anyone could make a fake ID
- With it, the library (Azure) can verify the ID is real

---

### Q2: Why output `resource_group_name` and `location` separately?

**Answer**: Terraform modules don't automatically share variables.

**The Challenge**:
```
AKS Module (creates cluster)
  - Knows: resource_group_name, location
  
Content-Service-Identity Module (creates managed identity)
  - Needs: resource_group_name, location
  - But doesn't have access to AKS module's variables!
```

**The Solution**:
```
AKS Module
  ↓ outputs these values
  ↓
Terragrunt Configuration
  ↓ passes them as inputs
  ↓
Content-Service-Identity Module
  ↓ uses them
```

**Why not hardcode?**
- Different environments use different resource groups
- Different regions use different locations
- Outputting makes it dynamic and reusable

---

### Q3: What does the content-service-identity module do?

**Answer**: It creates the Azure resources needed for managed identity authentication.

**Creates 3 things**:

1. **Managed Identity** - The "account" for your application in Azure
2. **Role Assignment** - Permissions to access storage
3. **Federated Credential** - The link between Kubernetes and Azure

**Why a separate module?**
- Keeps code organized
- Can be reused for other services (DIAL, Flink, etc.)
- Separates concerns (AKS module handles cluster, this handles identity)

---

### Q4: How are `content_service_client_id` and `content_service_sa_name` used?

**Answer**: They flow from Terraform to Helm to configure the application.

**Flow**:

```
Terraform
  ↓ Creates managed identity
  ↓ Gets client_id: "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
  ↓
  ↓ Writes to global-cloud-values.yaml:
  ↓   content_service_client_id: "xxxxxxxx..."
  ↓   content_service_sa_name: "content-service-sa"
  ↓
Helm
  ↓ Reads global-cloud-values.yaml
  ↓
  ↓ Creates ServiceAccount:
  ↓   name: content-service-sa
  ↓   annotation: azure.workload.identity/client-id: "xxxxxxxx..."
  ↓
  ↓ Creates Deployment:
  ↓   serviceAccountName: content-service-sa
  ↓   env: AZURE_CLIENT_ID: "xxxxxxxx..."
  ↓
Pod
  ↓ Uses these values to authenticate to Azure
```

---

### Q5: Why explicitly specify ServiceAccount name `"content-service-sa"`?

**Answer**: The name must match the federated credential in Azure.

**The Federated Credential says**:
```
"Trust tokens from ServiceAccount named 'content-service-sa' in namespace 'sunbird'"
```

**If we use a different name**:
```
ServiceAccount: "my-app-12345"  ❌
Azure: "I don't trust this - it's not 'content-service-sa'"
Result: Authentication fails
```

**With explicit name**:
```
ServiceAccount: "content-service-sa"  ✅
Azure: "I trust this - it matches my federated credential"
Result: Authentication succeeds
```

**Why not auto-generate?**
- Helm auto-generates names like `knowlg-knowledgebb-dev`
- These don't match the federated credential
- Explicit naming ensures consistency

---

### Q6: Why do we need the content-service-identity template?

**Answer**: To avoid duplicating configuration across environments.

**The Pattern**:

```
_common/content-service-identity.hcl
  ↓ Contains all the logic (100 lines)
  ↓
template/content-service-identity/terragrunt.hcl
  ↓ Includes the common config (7 lines)
  ↓
dev/content-service-identity/terragrunt.hcl
staging/content-service-identity/terragrunt.hcl
prod/content-service-identity/terragrunt.hcl
  ↓ Each just includes the template (7 lines each)
```

**Benefits**:
- Write once, use everywhere
- Update common config → all environments get the update
- Less code duplication
- Fewer errors

---

## Summary

### What We Changed

1. **AKS**: Enabled OIDC and Workload Identity
2. **New Module**: Created content-service-identity for managed identity
3. **Helm**: Updated to create ServiceAccount with managed identity annotations
4. **Configuration**: Added client ID to global values

### Why We Changed It

**Before**: Storage keys in ConfigMaps (security risk)  
**After**: Managed identity with automatic token rotation (secure)

### How It Works

1. Terraform creates managed identity in Azure
2. Terraform creates federated credential linking Kubernetes → Azure
3. Helm creates ServiceAccount with managed identity annotation
4. Pod uses ServiceAccount
5. Azure Workload Identity webhook injects tokens
6. Application authenticates to Azure using tokens
7. Azure grants access based on RBAC

---

**Questions?** Review the specific sections above or check the detailed guides in the artifacts directory!
