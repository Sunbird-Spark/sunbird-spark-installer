# Azure Infra Security Plan

Scope: the OpenTofu-managed cloud infrastructure for Azure (`opentofu/azure/`) plus
the scripts that provision/bootstrap it (`install.sh`, `create_tf_backend.sh`,
`private-repo-setup/scripts/setup-installer-vm.sh`). This does **not** cover
Kubernetes-internal security (RBAC inside the cluster, Kong/Keycloak
configuration, pod security standards, or whether individual `NetworkPolicy`
manifests are written correctly) — that is a separate, not-yet-started phase.
The one exception is #8 below: whether the cluster is even *capable* of
enforcing `NetworkPolicy` at all is an AKS resource setting, so it's in scope
here even though the policies themselves aren't reviewed.

Baseline already in place (verified, not re-litigated below): keyless workload
identity (federated credentials, no SA/storage keys), private AKS control
plane (`private_cluster_enabled`), Bastion/VPN-gated access, tfstate backend
storage account hardened (`--allow-shared-key-access false`, TLS1.2 minimum,
network-locked to the runner VM's subnet with `default-action Deny`).

Each finding below: **Why** it matters, **What** the fix is, **Impact** of
applying it (what breaks, what needs re-testing, whether it's a safe flag-flip
or a staged rollout).

---

## 1. No secrets manager — JWT/RSA keys and passwords live in plaintext YAML
**Severity: High** — **Status: Phase 1 implemented** (`modules/keys/main.tf`)

**Where:** `modules/keys/main.tf` (JWT signing key, RSA cert keypair),
`modules/random_passwords/main.tf` (Grafana/Superset/Keycloak admin
passwords) — all generated, then merged in plaintext into
`global-values.yaml`, then uploaded as a plaintext blob to the storage
account's private container (`az storage blob upload`).

**Why:** These are the actual signing keys for auth tokens and the admin
credentials for every dashboard in the stack. Anyone with read access to the
private container, the Terraform state, or the CI workspace during a run sees
them in the clear. There's no rotation story and no audit trail (Key Vault
logs every access; a blob download does not). The repo already has a comment
acknowledging this was considered and dropped (`# Sample code to enable
encryption... Encrypted files cannot be passed to helm`) — that constraint is
about the *file format*, not a reason to skip a secrets manager entirely.

**What was actually done (Phase 1 — additive, dual-write):**
- Added an `azurerm_key_vault` (`modules/keys/main.tf`): RBAC-authorized
  (`rbac_authorization_enabled`), purge protection on, firewalled to the
  AKS + runner subnets only (`network_acls`, same "selected networks"
  approach as the tfstate backend account rather than a Private Endpoint,
  which would be the further-locked-down option but adds a private DNS
  zone + VNet link dependency chain not taken on in this pass).
- Every JWT token and RSA keypair this module already generates is read
  back out of `global-values.yaml` right after generation and mirrored into
  the vault as a real secret (matched by shape — anything named `*_jwt`,
  `*_private_keys`, or `*_public_keys` — so it won't go stale if the
  consumer/prefix lists in `jwt-keys.py`/`rsa-keys.py` change).
- The 3 `random_passwords` module outputs (Grafana/Superset/Keycloak admin
  passwords) are mirrored in too, via a new `dependency "random_passwords"`
  wired through `keys.hcl`.
- The existing plaintext `global-values.yaml` merge and blob upload are
  **left untouched** — nothing consumes Key Vault yet, so nothing about the
  current install flow changes or can regress from this.
- The workload identity gets read-only access (`Key Vault Secrets User`,
  in `modules/workload-identity/main.tf`) so a later phase can point pods at
  it without another IAM change.
- The AKS + runner subnets got the `Microsoft.KeyVault` service endpoint
  added (`modules/network/main.tf`) — required for the vault's firewall
  allow-list to actually pass traffic; without it Azure silently drops the
  request instead of erroring.

**Deliberately not done in this pass (Phase 2, separate follow-up):**
rewiring every chart across the 6 building blocks to actually read from Key
Vault (via the Secrets Store CSI driver) instead of `global-values.yaml`,
and then removing the plaintext blob-upload path. That's the chart-by-chart
cutover the original plan flagged as its own migration project — doing it
blind, without a live cluster to test each chart against, risks breaking
JWT auth for whichever consumer gets missed. Phase 1 only adds the vault and
starts populating it; nothing reads from it yet.

**Not independently verified:** none of this has been run through
`tofu validate`/`apply` (no Azure CLI or credentials in this environment) —
checked by hand plus a couple of provider-schema lookups (`bypass` on
`network_acls` is a string not a list; `rbac_authorization_enabled` is the
current field name, `enable_rbac_authorization` is the deprecated one). Run a
real `plan` before trusting this.

---

## 2. Main storage account has no network ACL (only the tfstate backend does)
**Severity: High** — **Status: Evaluated, not implemented — see below for why.**

**Where:** `modules/storage/main.tf` — `azurerm_storage_account.storage_account`
has no `network_rules` block at all, so it's reachable from any network
(access is IAM-only). Compare with `create_tf_backend.sh`, which already does
exactly this for the *tfstate* storage account: `az storage account
network-rule add --subnet ... && az storage account update --default-action
Deny`.

**Why it looks like a gap:** This account holds the private container
(secrets — see #1), Velero backups, and content storage. Keyless RBAC is
good, but it means a leaked/over-privileged AAD token is enough to reach it
from anywhere on the internet. The backend storage account already proves
the pattern works in this codebase; the main data storage account just never
got the same treatment.

**Why it's not actually safe to apply as described:** `network_rules` on an
Azure storage account is account-wide — it can't be scoped to just the
private containers. This account also holds `storage_container_public`
(`container_access_type = "blob"`), served directly to end-user browsers at
`<account>.blob.core.windows.net` (see `object_storage_endpoint` in
`output-file`'s `.tfpl`, consumed by player/certificatesign/lern/knowlg/
flink). Confirmed against Microsoft's own docs, not just assumed: a
`network_rules{default_action=Deny}` firewall blocks anonymous public blob
reads too, even on a container explicitly set to public. Applying this as
originally scoped would take down public content delivery for every real
end user — the opposite of "low risk, stage the rollout."

**What's actually true today:** this storage account has no network-level
restriction, by necessity, not oversight. Access control for the private/
Velero containers is IAM-only: `shared_access_key_enabled = false`
(keyless) plus the container-scoped role assignments from #4. #7 below adds
a recovery layer (soft delete/versioning) on top of that, since a network
firewall isn't an option here.

**The real fix**, if this is worth doing: split the private/Velero
containers into their own storage account with its own firewall, leaving
the public container's account unrestricted.

**Reconfirmed, not just deferred:** that split isn't a pure-Terraform change
either — `global-cloud-values.yaml`'s `cloud_storage_access_key` is a single
field, read by `cert`, both `flink` charts, `secor`, and `knowledge-mw` for
private-container blob access, and by Velero's `backupStorageLocation`
config, all assuming one storage account. Splitting means adding a second
account-name field to that value file and updating every chart/job that
touches the private or Velero containers to use it instead — a change to the
Helm-consumed value contract, not just the OpenTofu module, and one this
plan's own stated scope (cloud-provisioning layer, not chart config)
excludes. Confirmed as out of scope for this pass rather than attempted
blind; needs its own tested follow-up with a live cluster to verify each
consumer.

---

## 3. AKS has no Azure AD RBAC integration — local accounts are the only gate
**Severity: Medium-High** — **Status: Rejected, by explicit decision**

Deliberately not implemented. Enabling this would mean everyone who needs
cluster access — including routine day-to-day access, not just emergency
break-glass — has to go through Azure AD/console role assignment first,
which is a real operational-friction tradeoff this team decided isn't worth
it right now. Leaving `local_account_disabled` unset (cluster stays
reachable via the standard admin kubeconfig) is a conscious choice, not an
oversight — revisit only if that tradeoff changes.

**Where:** `modules/aks/main.tf` / `variables.tf` — no
`azure_active_directory_role_based_access_control` block, no
`local_account_disabled`. Cluster access control is entirely at the Azure
resource level (whoever holds an "AKS Cluster Admin"-type role can pull a
full-admin kubeconfig via `az aks get-credentials`), with no
Kubernetes-native, Azure-AD-group-based RBAC layered on top.

**Why:** There's no way today to grant someone a *limited* in-cluster role
(e.g., read-only on one namespace) — the only lever is "can pull the admin
kubeconfig or not." Local accounts also bypass Azure AD's own audit trail for
who actually ran what against the cluster.

**What:** Set `azure_active_directory_role_based_access_control { managed =
true, azure_rbac_enabled = true }` and `local_account_disabled = true`.

**Impact:** **Breaking change for the current install flow** —
`install.sh`'s Helm steps rely on `az aks get-credentials` working
unauthenticated-beyond-ARM. Once local accounts are disabled, every
kubectl/helm call (including from CI) needs the caller's identity to hold an
Azure RBAC Kubernetes role ("Azure Kubernetes Service RBAC Cluster Admin" or
narrower). The runner VM's managed identity needs that role granted
explicitly, and the full install flow needs a dry run against a test cluster
before this lands on anything real — this is not safe to apply blind.

---

## 4. Workload-identity storage roles are account-scoped, not container-scoped
**Severity: Medium** — **Status: Implemented** (`modules/workload-identity/main.tf`)

**Where:** `modules/workload-identity/main.tf` — `Storage Blob Data
Contributor` and the custom `generateUserDelegationKey` role were both
assigned at `var.storage_account_id` (the whole account), not scoped to just
the containers a given workload actually needs.

**Why:** Broadens blast radius unnecessarily — a compromised pod using this
identity could read/write every container in the account (public content,
private secrets, Velero backups) rather than just the one it's meant to
touch. A user-delegation SAS can never grant more than the signing
principal's actual RBAC on the target container at generation time, so
scoping `Storage Blob Data Contributor` down to each container is what
actually bounds what a SAS minted through this identity can do.

**What was actually done:** `Storage Blob Data Contributor` is now a
`for_each` over the 3 containers (public/private/velero), scoped to
`${storage_account_id}/blobServices/default/containers/${container_name}`
each — no account-level grant of this role remains. Two things kept
deliberately account-scoped:
- `generateUserDelegationKey` (the custom role for SAS token issuance)
  **can't** be narrowed to a container — that action is defined at the
  storage account's blob-service level in Azure's own permission model,
  there's no container-scoped equivalent to assign it at.
- `Reader` stays account-scoped too, but for a different reason: it's an
  ARM management-plane role (resource metadata/endpoint discovery, e.g. for
  the Velero Azure plugin), not a data-plane grant — it can't read blob
  content, so the broader scope carries much less risk than Blob Data
  Contributor did.

**Verified against actual helm chart usage, not just the Terraform side:**
`cert`, both `flink` charts, and `secor` all write to the private container
via this identity — covered. `storage_container_public`/private/velero was
a complete list for *this* module. One thing this check surfaced that wasn't
part of this module at all: the `dial` addon
(`addons/dial/opentofu/azure/storage/main.tf`) creates its own 4th container
in the same storage account and grants access via its own separate role
assignment — unaffected by this change either way, since it's a different
Terraform resource. But that role assignment references a custom role,
`<env>-blob-operator-least-privilege`, that **no `azurerm_role_definition`
in this repo actually defines** — either it was created manually out-of-band,
or that addon's `apply` has always failed on this line. Not fixed here
(needs a live subscription to tell which), but it's the same class of issue
as #5 — worth checking in the same pass.

---

## 5. Custom role-assignment hygiene (carried over from the earlier portal audit)
**Severity: Low-Medium, cleanup** — **Status: Not executed — needs to be run
against the live subscription** (no Azure CLI/credentials available in the
environment this plan was written in)

**Why:** An earlier manual review of this subscription's IAM role
assignments (Azure Portal listing) turned up assignments with `Unknown`
principal type — i.e. pointing at an identity that's since been deleted —
plus a few assignments broader than anything the current Terraform actually
requires.

**What:** Re-run `az role assignment list --all --output json`, cross-check
every assignment against a module or script that genuinely needs it, delete
the `Unknown`-principal ones outright (they're already non-functional dead
weight), and leave a one-line comment on each surviving custom role
definition stating what consumes it.

**Impact:** Deleting `Unknown`-principal assignments is zero-risk — they do
nothing today by definition. Anything else flagged as "broader than
Terraform requires" needs a one-by-one check before removal (some may back
manual/emergency-access paths that aren't in Terraform at all).

**Run this yourself** (needs `az login` with an account that has
`Microsoft.Authorization/roleAssignments/*` on the subscription):

```bash
# 1. List every assignment, flag the orphaned ones (Unknown principal type
#    means the identity behind it has since been deleted).
az role assignment list --all --output json \
  | jq '[.[] | select(.principalType == "Unknown")]'

# 2. For each one from step 1, confirm it's really dead, then delete by its
#    own ID (safer than matching on name/role, which can collide):
az role assignment delete --ids <assignment-id-from-step-1>

# 3. Separately, list custom role definitions in this subscription and
#    cross-check each against what Terraform actually creates/consumes
#    (e.g. the ones this repo defines: user_delegation_key in
#    workload-identity, plus whatever the runner-VM bootstrap scripts
#    created) before touching anything not already known to be Unknown.
az role definition list --custom-role-only true --output table
```

---

## 6. No subnet-level NSGs on the AKS/runner subnets (only the VM has one)
**Severity: Low** — **Status: Implemented, partially** (`modules/network/main.tf`)
— `aks_subnet` only; `runner_subnet` deliberately excluded, see below.

**Where:** `modules/network/main.tf` — `aks_subnet` and `runner_subnet` had
no `azurerm_network_security_group` attached. The only NSG anywhere in the
Azure infra was the one Azure auto-creates for the runner VM's NIC
(`private-repo-setup/scripts/setup-installer-vm.sh`), scoped to just that
VM's two VPN ports.

**Why:** This is common for AKS (pod/node traffic needs to flow relatively
freely, and public exposure is already gated by the LB/ingress + private
control plane), but "common" isn't the same as "evaluated for this specific
setup." It was an absence, not a documented decision.

**What was actually done:** Added a defaults-only
`azurerm_network_security_group` (no custom rules — just Azure's own
`AllowVnetInBound`/`AllowAzureLoadBalancerInBound`/`DenyAllInBound`,
unrestricted outbound) to `aks_subnet`. No hand-written AKS required-ports
allow-list — AKS nodes have no public IPs, so the defaults already match
real traffic here, and a hand-written list can't be validated without a live
cluster.

**Why `runner_subnet` was deliberately left out:** When `vpn_enabled = true`
(the default), the runner VM has a public IP with UDP 1194 + TCP 443 open to
the internet at the NIC level, for the VPN server that's the only way into
this environment. Azure's default NSG rules have no internet-inbound allow
(only VirtualNetwork/AzureLoadBalancer) — a subnet-level NSG here would sit
alongside the existing NIC-level one, and since both must permit traffic, the
subnet-level deny would silently block all VPN connections. This was caught
before applying it, not after. The NIC-level NSG already scopes this VM
correctly on its own; a redundant subnet-level NSG isn't worth that risk.

---

## 7. Neither storage account had soft delete or versioning
**Severity: Medium** — **Status: Implemented** (`modules/storage/main.tf`,
`create_tf_backend.sh`)

**Where:** `azurerm_storage_account.storage_account`'s `blob_properties`
block had a `cors_rule` but no `versioning_enabled` or
`delete_retention_policy` — same gap on the tfstate backend account created
imperatively in `create_tf_backend.sh`.

**Why:** The main storage account can't be network-firewalled (#2) and the
tfstate account, while firewalled, still has no recovery path of its own —
so for both, an authorized-but-buggy consumer, a bad `apply`, or a
compromised identity that overwrites or deletes a blob (JWT/RSA keys,
tfstate itself, Velero backups, public content) causes silent, permanent
loss today.

**What was actually done:** Added `versioning_enabled = true`,
`delete_retention_policy { days = 30 }`, and
`container_delete_retention_policy { days = 30 }` to the main storage
account's `blob_properties` block; added the equivalent
`az storage account blob-service-properties update --enable-versioning
--enable-delete-retention --enable-container-delete-retention` call to
`create_tf_backend.sh` for the tfstate account.

**Impact:** Additive only — no access-control change, no effect on
anonymous public reads on `storage_container_public`, safe to apply without
staging. Storage cost goes up slightly (soft-deleted versions are billed
until they age out at 30 days).

---

## 8. AKS has no NetworkPolicy engine — the charts' NetworkPolicy resources are inert
**Severity: High — found, NOT implemented (see Impact)** — **Status: Rejected
for this pass by explicit decision, re-confirmed given the auto-approve risk
below — needs a staged rollout against a test cluster before it's ever safe
to apply**

**Where:** `modules/aks/main.tf` — `network_profile` sets `network_plugin`,
`network_plugin_mode = "overlay"`, `service_cidr`, and `dns_service_ip`, but
never sets `network_policy`. Meanwhile the Helm charts across the 6 building
blocks ship real `NetworkPolicy` resources (pod-to-pod traffic restrictions).

**Why this matters:** A Kubernetes `NetworkPolicy` object does *nothing* by
itself — it's only enforced if the cluster's CNI has a network policy engine
running. AKS does not enable one by default. That means every `NetworkPolicy`
already shipped in these charts is currently a no-op: pods can reach each
other exactly as freely as if none of those manifests existed. This wasn't
caught by the original plan because it reads as "Kubernetes-internal, out of
scope" — but *whether the engine exists at all* is an AKS resource setting,
squarely in this plan's actual scope (cloud provisioning), even though the
policies' own correctness isn't reviewed here.

**What the fix would be:** Set `network_policy = "calico"` in
`azurerm_kubernetes_cluster.aks.network_profile`. Calico, not `"azure"` —
Azure's own Network Policy Manager does not support `network_plugin_mode =
"overlay"`, which this cluster already uses; Calico is the option compatible
with overlay mode.

**Why this is NOT implemented in this pass:** `network_policy` is a
`ForceNew` field on `azurerm_kubernetes_cluster` in the AzureRM provider —
changing it on an already-provisioned cluster destroys and recreates the
entire AKS cluster, not an in-place update. That's a full-outage, high-blast-
radius change for every environment already deployed with this Terraform,
and this repo has no live cluster here to validate the resulting policy
enforcement against (would every chart's existing `NetworkPolicy` actually
permit the traffic it needs, or has something been relying on the absence of
enforcement?). Not safe to apply blind.

**Recommended path:** treat as a planned, scheduled migration per
environment (announce a maintenance window, recreate the cluster with
`network_policy = "calico"` set from the start, verify every building block
still functions against the newly-enforced policies) rather than a
`tofu apply` surprise.

**Reconfirmed, not just deferred:** `install.sh` runs
`terragrunt apply --auto-approve` — so setting this in the shared module
now, even to only affect *new* environments, means the very next
`create_tf_resources` run against any **existing** environment would
silently plan (and auto-apply, no human sees the plan first) a destroy +
recreate of that environment's AKS cluster. Given that, this stays
unimplemented in the module itself, not just documented as a future
migration — explicit decision, re-confirmed, same category as #3.

---

## 9. AKS had no Azure Policy add-on
**Severity: Low — capability gap, not an active exposure** — **Status:
Implemented** (`modules/aks/main.tf`)

**Where:** `azurerm_kubernetes_cluster.aks` had no `azure_policy_enabled`
attribute (defaults to `false`).

**Why:** Without the add-on, there's no way to assign Azure Policy
initiatives against the cluster — e.g. the built-in "Kubernetes cluster pod
security baseline standards" initiative, which is the standard low-effort
way to get audit (and eventually enforcement) of things like
privileged-container use or hostPath mounts across every building block at
once, without writing OPA/Gatekeeper policies by hand.

**What was actually done:** Set `azure_policy_enabled = true`. This only
turns on the add-on infrastructure (the Gatekeeper-based policy engine) —
**no policy initiative is assigned in this change**, so nothing in the
cluster's actual behavior changes yet. Assigning an initiative (audit-mode
first, ideally) is a follow-up once there's a live cluster to check the
audit results against before ever turning on enforcement.

**Impact:** Safe, in-place toggle — `azure_policy_enabled` is not `ForceNew`,
unlike #8's `network_policy`. No behavior change until a policy/initiative
is actually assigned.

---

## Sequencing recommendation

Not all of these are equally safe to do in one pass:

1. **#5 (orphaned role cleanup)** — zero-risk, do first, any time. **Not yet
   executed** — needs to be run against the live subscription; commands are
   above.
2. **#7 (blob soft delete/versioning)** — **implemented**, purely additive,
   no staged rollout needed.
3. **#4 (narrow workload-identity storage scope)** — **implemented**.
4. **#1 (Key Vault Phase 1)** — **implemented** (vault stands up, secrets
   get mirrored into it, nothing consumes it yet — see #1 for what's
   deferred to Phase 2 and why).
5. **#9 (Azure Policy add-on)** — **implemented**, in-place toggle, no
   policy initiative assigned yet.
6. **#6 (subnet NSGs)** — **implemented, partially** — `aks_subnet` gets a
   defaults-only NSG; `runner_subnet` deliberately excluded (would have
   silently blocked the VPN's internet-facing inbound — caught before
   applying it).
7. **#2 (storage network ACL)** — **rejected, re-confirmed** — this account
   has a legitimately public container, an account-wide firewall breaks
   public content delivery; the real fix (splitting accounts) also touches
   the Helm value contract, not just Terraform. #7 covers the recovery
   angle instead.
8. **#3 (AAD RBAC on AKS, disable local accounts)** — **rejected by explicit
   decision**: it would mean everyone needing cluster access has to go
   through Azure AD/console role assignment, which isn't a tradeoff this
   team wants right now.
9. **#8 (AKS NetworkPolicy engine)** — **found, rejected for this pass,
   re-confirmed** — the fix is `ForceNew` (destroys/recreates the cluster),
   and `install.sh` runs `terragrunt apply --auto-approve`, so setting it
   now would silently destroy any existing environment's AKS cluster on the
   next `create_tf_resources` run. Needs a planned, human-supervised
   migration window per environment instead.

**Net:** #1, #4, #6 (partial), #7, #9 are implemented in this branch's code
(none apply-tested — no Azure CLI/credentials in this environment). #2, #3,
#8 are explicit, re-confirmed decisions not to act. #5 needs a manual run
against the live subscription — genuinely can't be done from this
environment at all (no Azure CLI, no credentials, no network access to
Azure), not a risk tradeoff.

## Explicitly out of scope of this plan

Kubernetes-internal security was not reviewed here: in-cluster RBAC bindings,
whether the charts' `NetworkPolicy` resources themselves are correctly
written (only *whether the cluster can enforce them at all* was in scope —
see #8), Kong Gateway auth config, Keycloak realm settings, pod security
standards, and secret handling *inside* the cluster (as opposed to how
secrets get into it, covered in #1). None of that has been audited yet —
treat "infra secure" claims from this plan as scoped to the cloud-
provisioning layer only, not the full platform.
