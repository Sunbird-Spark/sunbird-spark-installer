### GCP

Follow this document if you are setting up Sunbird-Ed on GCP

#### Required tools and permissions
1. Google Cloud CLI (https://cloud.google.com/sdk/docs/install)
2. Ensure that the user or service account running the Terraform script has the necessary privileges as [listed here](https://registry.terraform.io/providers/hashicorp/google/latest/docs/guides/provider_reference#authentication).

**Note:**
We will overwrite the following files. Please take a backup of your existing files in the following locations:
- `~/.config/rclone/rclone.conf`

### Authentication

Post installation of the CLI tool and providing necessary permissions, use the following commands to login to GCP via CLI:

```
gcloud auth login
```

Then initialize the GCP configuration:

```
gcloud init
```

Authenticate the application with default credentials:

```
gcloud auth application-default login
```

Install the GKE gcloud authentication plugin:

```
gcloud components install gke-gcloud-auth-plugin
```

Export the project ID as an environment variable:

```
export GOOGLE_PROJECT_ID=<your_project_id>
```

Note: Make sure you select the correct project and authenticate with the appropriate credentials.

## GKE Kubernetes Version Upgrade

The GKE cluster is provisioned with a Kubernetes version defined in `opentofu/gcp/modules/gke/variables.tf`. By default it is set to `"latest"`, which picks the latest available version in the selected region at cluster creation time. GKE versions have a support lifecycle of approximately **12 months** after GA. When a version approaches end of life, you must upgrade to a supported version.

### When to Upgrade

GKE supports the **3 latest GA minor versions** at any time. Once your version falls outside this window, Google may auto-upgrade your cluster. It is recommended to upgrade proactively before that happens.

Check the currently supported GKE versions at: https://cloud.google.com/kubernetes-engine/docs/release-notes

### How to Upgrade

**Step 1 — Update the `kubernetes_version` default in `opentofu/gcp/modules/gke/variables.tf`:**
```hcl
variable "kubernetes_version" {
  description = "The Kubernetes version of the masters."
  type        = string
  default     = "<new-version>"  # e.g. "1.34"
}
```

**Step 2 — Apply via OpenTofu:**
```bash
cd opentofu/gcp/<env>/gke
terragrunt apply
```

> **Note:** GKE only supports upgrading **one minor version at a time** (e.g., 1.33 → 1.34 → 1.35). You cannot skip versions.

---

### Creating infrastructure using OpenTofu

The installer can be run on one of the following platforms:
- Linux
- MacOS
- Windows (requires Git for Windows https://gitforwindows.org/)

#### Required CLI tools
1. Google Cloud CLI (https://cloud.google.com/sdk/docs/install)
2. jq (https://jqlang.github.io/jq/download/)
3. rclone (https://rclone.org/)
4. OpenTofu (https://opentofu.org/docs/intro/install/)
5. Terragrunt (https://terragrunt.gruntwork.io/docs/getting-started/install/)
6. Python 3 (https://www.python.org/downloads/)
7. PyJwt python package (https://pypi.org/project/PyJWT/)
8. Postman CLI (https://learning.postman.com/docs/postman-cli/postman-cli-installation/)

#### CLI Versions
The installer doesn't require a specific CLI version, but we have documented the versions used and verified. If a future release of a CLI tool introduces a breaking change, it may result in installation failure. Please raise a GitHub issue if you encounter such an issue.

#### OpenTofu Backend Setup

```
git clone https://github.com/project-sunbird/sunbird-ed-installer.git
cd opentofu/gcp
gcloud auth login
gcloud config set project <your_project_id>
```

#### GCP Infra Setup

Post login, update the `opentofu/gcp/<env>/global-values.yaml` file with the variables as per your environment:

```
building_block: "" # building block name
env: ""
environment: "" # use lowercase alphanumeric string between 1-9 characters
gke_cluster_location: ""
zone: ""
gke_node_pool_instance_type: ""
domain: ""
sunbird_google_captcha_site_key: ""
google_captcha_private_key: ""
sunbird_google_oauth_clientId: ""
sunbird_google_oauth_clientSecret: ""
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

Then run the following OpenTofu commands:

```
cd opentofu/gcp/dev
terragrunt init
terragrunt run-all validate
terragrunt run-all plan
# Enter y in the next command
terragrunt run-all apply
```

