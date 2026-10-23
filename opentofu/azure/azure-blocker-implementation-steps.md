# Azure CSPM BLOCKER Findings — Implementation Steps

Ordered, step-by-step runbook for closing the 65 BLOCKER resources. Read
`azure-blocker-fixes.md` first for the *why* behind each step — this file is the
*in what order, do what* checklist. Do not skip ahead — steps 3 onward are
sequenced on purpose; doing them out of order breaks content loading or uploads for
every learner.

---

## Step 1 — HTTP(S) NSG (Network Security Group) review (independent, no dependency)

Closes: "HTTP(S) access from the Internet should be restricted" (4 resources).

1. List the 4 flagged NSGs via `az network nsg list` / the CSPM report's resource IDs.
2. Identify which one fronts `nginx-public-ingress` — leave it untouched.
3. For each of the remaining NSGs, list their inbound rules and check whether any
   rule allows port 80/443 from source `*`.
4. For each overly broad rule found, determine the actual source that needs access
   (a specific admin range, another internal service, etc.) and narrow the rule to
   that source.
5. Re-run the CSPM scan (or manually re-check `az network nsg rule list`) to confirm
   the finding clears on the non-ingress NSGs.

Fix: `sunbird-spark-installer/opentofu/azure/cspm-fixes/review-public-http-nsgs.sh`
Can run in parallel with Step 2 — no shared dependency. | one time fix for the live cluster.
link: https://github.com/sho6000/sunbird-spark-installer/commit/66e6e8c6bc30d7eb090ddf624f05d2e244fc6b59

---

## Step 2 — Phase 1 groundwork: internal AKS → storage access (no behavior change)

Prerequisite for everything from Step 4 onward. Closes nothing by itself.
**Notes:**
- the subnet's side. This is where I hit a real wall. For the "private road" to work, the AKS subnet itself needs that Service Endpoint feature turned on. I found that this repo's code handles subnets in two different ways depending on how an environment is set up:
- If Terraform creates a brand-new network from scratch, it already turns this feature on — no problem there.
- If Terraform instead reuses a network that already exists (which real environments like yours very likely do, since you wouldn't want Terraform building you a whole new network), the code only reads that existing subnet — it never owns or changes it.
---
- Terraform creates a fresh VNet (skip_network_module: false) and use Pritunl VPN for access (vpn_enabled: true)
- Terraform creates a fresh VNet (skip_network_module: false) and use Bastion instead (vpn_enabled: false)
---
- skip_network_module: false → Terraform is creating the VNet/subnet from scratch anyway, so it already bakes the Microsoft.Storage service endpoint in as part of that creation (network/main.tf:64) — this was already true before any of today's work, nothing new needed. The one-time script sees this setting and just prints "nothing to do, Terraform already handles it" and exits.
- skip_network_module: true → the subnet already exists and Terraform only reads it (doesn't create/own it), so it can't safely add the service endpoint itself. That's where the script kicks in: it reads vnet_name, aks_subnet_name, and resource_group_name straight out of global-values.yaml for that environment, and uses those exact values to run the az command against that specific real subnet.
---
- skip_network_module: true → the script checks global-values.yaml, sees true, reads the subnet details, checks/adds the service endpoint via az — does real work.
- skip_network_module: false → the script checks global-values.yaml, sees false, prints "nothing to do, Terraform already handles it," and exits immediately — no az calls, does nothing.


1. In `opentofu/azure/modules/network/main.tf`, fix the `skip_network_module: true`
   branch (the `data "azurerm_subnet" "aks_subnet"` block, currently ~line 35-40) so
   it also verifies/enables the `Microsoft.Storage` service endpoint on the existing
   AKS subnet — today only the Terraform-creates-the-VNet branch (line 64) sets this.
2. In `opentofu/azure/modules/storage/main.tf`, add a `network_rules` block to
   `azurerm_storage_account.storage_account`:
   - `default_action = "Allow"` for now (do **not** flip to Deny yet — that's Step 6)
   - `virtual_network_subnet_ids = [<aks_subnet_id>]` so the exception is already in
     place before it's ever needed
3. Wire the AKS subnet ID into the storage module's inputs via
   `opentofu/azure/_common/storage.hcl` (same `dependency "network"` pattern already
   used for `resource_group_name`).
   
### Order of execution (matters for `skip_network_module: true`)

Azure requires a subnet to already have the `Microsoft.Storage` service endpoint
enabled before it can be referenced as a storage account network-rule exception —
you can't add the exception first and the endpoint second. `default_action` stays
`"Allow"` throughout, so nothing live ever breaks either way, but applying out of
order will fail the `apply` itself (not production, just a blocked deployment) until
re-run in the right order.

- **`skip_network_module: false`** — no action needed. Terraform creates the subnet
  with the endpoint already enabled, before the storage module ever runs (existing
  `network` → `storage` dependency order already guarantees this).
- **`skip_network_module: true`** — run in this exact order:
  1. `cspm-fixes/enable-storage-service-endpoint.sh --apply` (confirms/adds the
     service endpoint on the real subnet first)
  2. `terragrunt apply` on the storage module (adds the network-rule exception,
     which now has a valid subnet to point at)

4. Apply and confirm via `az storage account network-rule list` that the rule exists,
   with default action still `Allow` (nothing should be blocked yet).

---

## Step 3 — Decide CDN vs. Azure Front Door, then stand it up

Prerequisite for Steps 4 and 5.

### The three option types, compared

- [Azure CDN (classic)](https://azure.microsoft.com/en-us/products/cdn) — [retirement FAQ](https://learn.microsoft.com/en-us/azure/cdn/classic-cdn-retirement-faq)
- [Azure Front Door](https://azure.microsoft.com/en-us/products/frontdoor/) (Standard and Premium tiers) — [pricing](https://azure.microsoft.com/en-us/pricing/details/frontdoor/)

| | Azure CDN (classic) | Front Door Standard | Front Door Premium |
|---|---|---|---|
| Status | **Retiring** — no new profiles accepted since Aug 2025, full retirement Sept 2027 | Current, supported | Current, supported |
| Base monthly fee | No flat base (pure usage-based) | $35/month | $330/month |
| Data transfer (egress) | ~$0.081/GB first 10TB (NA/Europe) | $0.083/GB first 10TB, tiered down from there | Same tiered rate as Standard |
| Request fee | N/A (different billing model) | $0.009 / 10,000 requests | $0.015 / 10,000 requests |
| WAF | Not integrated | Custom rules only | Custom rules + managed rule sets |
| Private Link to origin | ❌ Not supported | ❌ **Not supported** | ✅ Supported |
| Can close Group A (Step 6, network-deny, 20 resources) | ❌ No | ❌ **No** — confirmed via Microsoft Q&A, `Microsoft.Cdn/profiles` isn't a valid storage network-rule exception, so there's no way to reach a fully-denied storage account without Private Link | ✅ Yes — only tier that can |
| Can close Group B (Step 4, anonymous access/39 containers, 41 resources) | ✅ Yes | ✅ Yes | ✅ Yes |

**Decision (resolved, no longer an open question): Azure Front Door Premium.**
Ruled out classic Azure CDN (retiring, not viable for new builds). Front Door
Standard is cheaper ($35/month vs. $330/month base, same egress rate) but cannot
close the Group A network-ACL findings without a workaround (allowlisting the Front
Door service tag + inspecting the `X-Azure-FDID` header at the application layer),
which is an application-level check, not a true network-level deny — it wouldn't
actually satisfy "public network access disabled." Since fully closing all 65
BLOCKER findings (not just the biggest one) is the goal, Premium's Private Link
support makes it required, not optional. At genuine scale, the identical per-GB
egress cost will likely dwarf the $295/month base-fee difference anyway.

1. Create the Front Door Premium profile and endpoint, with the public blob
   container as origin.
2. Create a Private Link connection from Front Door to the storage account, and
   approve the private endpoint connection on the storage side.
3. Grant Front Door's managed identity the `Storage Blob Data Reader` role on the
   storage account (needed once anonymous access is later disabled in Step 4).
4. Set up a custom domain + TLS certificate on the Front Door endpoint if replacing
   the raw blob hostname with your own domain (rather than the default
   `*.azurefd.net` hostname).
5. Validate: fetch a known test blob through the new Front Door hostname and
   confirm it returns the correct content, **before touching any service config**.

### Belongs in Terraform eventually

Front Door is new infra every deployer needs (unlike the one-off NSG/VM fixes) — it
should become `opentofu/azure/modules/cdn/`, same pattern as `storage`/`aks`/
`security-baseline`. Commands below are the manual proof-out first.

### Commands

```bash
# 1. Profile, endpoint, origin group, origin
az afd profile create --profile-name sunbird-frontdoor --resource-group <rg> --sku Premium_AzureFrontDoor
az afd endpoint create --endpoint-name sunbird-content --profile-name sunbird-frontdoor --resource-group <rg>
az afd origin-group create --origin-group-name storage-origin-group --profile-name sunbird-frontdoor \
  --resource-group <rg> --probe-request-type GET --probe-protocol Https --probe-interval-in-seconds 60
az afd origin create --origin-name storage-origin --origin-group-name storage-origin-group \
  --profile-name sunbird-frontdoor --resource-group <rg> \
  --host-name <storage-account>.blob.core.windows.net --origin-host-header <storage-account>.blob.core.windows.net

# 2. Private Link + approval (approval is manual, Azure won't auto-approve cross-resource)
az afd origin update --origin-name storage-origin --origin-group-name storage-origin-group \
  --profile-name sunbird-frontdoor --resource-group <rg> --enable-private-link true \
  --private-link-resource <storage-account-resource-id> --private-link-location <region> --private-link-sub-resource-type blob
az network private-endpoint-connection approve --resource-group <rg> --name <connection-name> \
  --resource-name <storage-account> --type Microsoft.Storage/storageAccounts

# 3. Grant read access
az role assignment create --assignee <frontdoor-identity-principal-id> \
  --role "Storage Blob Data Reader" --scope <storage-account-resource-id>

# 4. Custom domain + route (optional)
az afd custom-domain create --custom-domain-name sunbird-cdn --profile-name sunbird-frontdoor \
  --resource-group <rg> --host-name cdn.sunbird.org --certificate-type ManagedCertificate
# add CNAME at DNS: cdn.sunbird.org -> Front Door endpoint
az afd route create --route-name content-route --endpoint-name sunbird-content --profile-name sunbird-frontdoor \
  --resource-group <rg> --origin-group storage-origin-group --supported-protocols Https --https-redirect Enabled

# 5. Validate
curl -I https://sunbird-content-<hash>.z01.azurefd.net/<public-container>/<some-known-file>
# expect 200 OK, before touching any of the 5 services in Step 4
```

**To verify before building the Terraform module:** does
`azurerm_cdn_frontdoor_origin`'s `private_link` block auto-approve the private
endpoint connection, or does that need its own step? Check current `azurerm` docs,
confirm with `tofu plan`.

---

## Step 4 — Migrate reads to the CDN, then close Group B findings

Closes: "Allow Blob Anonymous Access should be Disabled" (2) + "Public access level
should be Private for blob containers" (39) = 41 resources.

---

**Extending it for Front Door — same pipe, one new value:**
1. The new modules/cdn (Step 3) outputs the Front Door hostname.
2. output-file's template (global-cloud-values.yaml.tfpl) gets a new field, e.g. front_door_hostname, sourced from that output — same pattern as azure_storage_account_name is today.
3. Each chart's config (player/configs/env.yaml, knowlg/.../application.conf, etc.) gets updated to reference {{ .Values.global.front_door_hostname }} instead of building the URL from the raw storage endpoint.

---

1. Update config for each of the 5 consuming services to point at the new CDN
   hostname instead of the raw blob endpoint:
   - `player` — `helmcharts/edbb/charts/player/configs/env.yaml:26`
     (`SUNBIRD_CLOUD_STORAGE_URLS`)
   - `knowlg` — `helmcharts/knowledgebb/charts/knowlg/configs/application.conf:265,390-408`
   - `lern` — `helmcharts/learnbb/charts/lern/configs/env.yaml:61-69,166-171,196`
   - `cert` — `helmcharts/learnbb/charts/cert/configs/env.yaml:3-22`
   - `sync-tool` — same pattern as knowlg
2. Roll this out to a non-production environment first; confirm content actually
   loads end-to-end through the CDN path for each service.
3. Scope the data migration: query the database(s) for how many stored records
   reference the old raw blob URL pattern. Decide: bulk rewrite job, or a redirect
   kept alive at the old hostname for some transition window.
4. Execute the chosen data migration strategy; verify a sample of previously-stored
   content URLs resolve correctly post-migration.
5. Roll the config change to production once validated in staging.
6. Only after reads are confirmed fully served via the CDN in production: disable
   "Allow Blob Anonymous Access" at the account level.
7. Flip each of the 39 flagged containers' access level to `Private`.
8. Re-verify content still loads for learners (now via CDN + authenticated origin
   fetch, not anonymous blob access) before considering this step done.

---

## Step 5 — Replace direct-to-blob uploads with backend-mediated uploads

Prerequisite (alongside Step 4) for Step 6. No CSPM control closes directly from
this step alone — it unblocks Step 6.

### Options considered

**Option A — Route uploads through Front Door Premium (no application code changes)**
Browser still gets a SAS URL and PUTs to it, but the URL points at Front Door
instead of raw storage; Front Door relays the write to storage via the Private Link
already built in Step 3. Lowest effort, but large-file-upload reliability/size
limits through this path aren't confirmed against current Azure docs — it's a less
common use of Front Door than read-caching.

**Option B — A small, dedicated upload-relay service (RECOMMENDED)**
Build a new, minimal service whose only job is "receive a file, write it to blob
storage" — a new Helm chart in this repo (own container, own small codebase), not a
change to the existing `knowlg-service`/`ml-core-service` codebases. Kong routes
upload traffic to this new service instead. Keeps the change small, isolated, fully
within this repo's existing pattern (new chart + container), and doesn't require
touching or redeploying larger services owned by other teams.

**Option C — Accept the gap, skip Steps 5 and 6 for uploads**
Leave storage's network rule allowing public access for uploads only; close
everything else (Step 4's 41 resources). Zero new code, but Group A's 20 network-ACL
findings stay open indefinitely.

**Why B over A and C:**

| | A (Front Door relay) | B (new relay service) | C (accept the gap) |
|---|---|---|---|
| New code needed | Minimal | Some (small, isolated) | None |
| Fully closes all 65 findings | Maybe — unverified | **Yes** | No — 20 stay open forever |
| Risk | Relies on an unconfirmed Azure capability for large file uploads | Low — uses a well-proven pattern (Kong → backend service → storage) already used everywhere else in this repo | None technically, but leaves real exposure open |
| Touches existing services | No | No | No |

A's problem: least work, but it bets uploads — a critical function — on an Azure
capability I couldn't confirm actually works reliably (Front Door Premium proxying
large file PUTs through Private Link). C's problem: zero work, but a third of the
total security findings (20 of 65) never get fixed. B is the only option that gets
to fully closing every finding without betting on something unverified.

### Steps (assuming Option B)

1. Design the new upload flow: browser sends file bytes to Kong → routed to a new
   lightweight upload-relay service → that service writes the file to blob storage
   itself (using a `Storage Blob Data Contributor` role via workload identity, same
   pattern already used elsewhere in this repo), instead of minting a SAS URL for
   the browser to PUT directly.
2. Build the new service: a minimal app that accepts a file upload (streamed, not
   fully buffered, for large files) and writes it to blob storage. New Helm chart in
   this repo, following the existing chart structure/conventions.
3. Update the relevant Kong routes (`uploadUrlAsset`, `uploadUrlContentV2/V3`,
   `getContentUploadUrl`, `getFileUploadUrls` in
   `helmcharts/edbb/charts/kong-apis/configs/kong-apis.yaml`) to point at the new
   service instead of the existing backend services.
4. Check and raise Kong's request body size limits if needed — the gateway will now
   be passing full file payloads through, not just small JSON requests for a URL.
5. Update any client/frontend code that currently does "fetch SAS URL, then PUT
   directly to it" to instead upload through the new endpoint.
6. Test uploads end-to-end in a non-production environment: small files, large
   files, concurrent uploads.
7. Roll out to production; monitor for upload failures/timeouts before proceeding.

---

## Step 6 — Final cutover: deny public network access on storage

Closes: "Default network access rule should be set to deny" (4) + "Public network
access should be disabled" (6) + "Storage account public access disallowed" (6) +
"Storage accounts should restrict network access" (4) = 20 resources.

Do not start this step until Step 4 (reads via CDN) **and** Step 5 (uploads via
backend) are both live in production and validated.

1. Confirm one more time: no service or client anywhere still depends on reading
   from or writing to the storage account over its public endpoint directly.
2. In `opentofu/azure/modules/storage/main.tf`, change the `network_rules` block's
   `default_action` from `Allow` to `Deny` (the AKS subnet exception from Step 2 and
   the CDN's Private Link/resource-access exception from Step 3 remain in place).
3. Apply in a non-production environment first; run a full smoke test — content
   loads via CDN, uploads succeed via the new backend-mediated path, internal
   services (knowlg, lern, cert) still function.
4. Roll out to production.
5. Re-run the CSPM scan to confirm all 4 network-ACL controls now show compliant.

---

## Step 7 — Final verification

1. Re-run the full CSPM scan against the subscription.
2. Confirm all 65 BLOCKER resources now show resolved (or re-scope anything that
   doesn't match expectations).
3. Update `azure-blocker-fixes.md` and this file with any deviations encountered
   during implementation, so the record stays accurate for future reference.

---
---
---

1. HTTP(S) access from the Internet should be restricted (4 resources)

What it checks: Azure scans every NSG (network firewall) in the subscription for rules that allow HTTP (port 80) or HTTPS (port 443) traffic from source * — meaning literally any IP address on the internet.

Why it's flagged: Wide-open HTTP(S) rules are a common way attackers probe for exploitable web services. In general, you want every inbound rule scoped to only what's actually needed.

Why it's tricky here: One of your NSGs — the one in front of nginx-public-ingress — is supposed to accept HTTP(S) from anyone on earth. That's the entire point of a public learning platform: anyone can load a course page without a VPN or allowlist. If you ran a blanket "restrict all HTTP(S) to known IPs" fix, you'd accidentally also lock down the ingress and the whole platform goes dark for every learner.

What this finding actually means: The CSPM report almost certainly means "the other 3 NSGs shouldn't have HTTP(S) wide open" — not the ingress. But the report doesn't tell you which NSG is which.

How we're fixing it: A manual review — go through each of the 4 flagged NSGs one at a time, identify the one that's the public ingress (leave it alone), and for the rest, check if HTTP(S) actually needs to stay open to the world or can be scoped to specific sources. No code change, no architecture decision — just a careful audit.

---
2. (Prep step, not a CSPM control) — AKS-to-storage internal access

What this is: Not one of the 7 blocker findings itself, but a prerequisite everything else depends on.

The problem: Right now, backend services running inside your Kubernetes cluster (knowlg, lern, cert) read and write to the storage account over the public internet path, even though they're technically running "inside" your infrastructure. Once we lock down storage's network access (which is the whole point of the other 6 findings), these backend services need a way to keep reaching storage that doesn't depend on the public path.

How we're fixing it: Azure has a feature called a VNet Service Endpoint — it lets you say "this specific subnet (where AKS lives) gets a private, Azure-backbone path into this storage account, without going over the public internet." We found that this repo's Terraform only sets this up when it's creating a brand-new virtual network — if you're reusing an existing VNet (which real environments likely do), this protection silently never gets configured. We're fixing both: adding the storage-side permission entry (network_rules allowing that subnet), and fixing the gap so the VNet setting actually gets applied regardless of which path you take.

Why it's safe to do now: This step alone doesn't change what's blocked or allowed yet — storage still accepts public traffic until later. It's pure preparation.

---
3. Allow Blob Anonymous Access should be Disabled (2 resources)

What it checks: There's an account-wide switch on a storage account called "Allow Blob Anonymous Access." If it's turned on, it means any container on that account is allowed to be set to public — it's the master switch that makes public containers possible at all. If it's off, no container could be made public even by accident, ever.

Why it's flagged: It's a broader exposure than any single container's setting — it's the permission that makes public containers possible as a category.

Why it's a blocker today: If your learner-facing public content lives on either of these 2 accounts (it does), flipping this off immediately breaks anonymous reads of that content — before you've built anything to replace it.

How we're fixing it: This is where the "CDN for reads" project comes in. Once a CDN sits in front of the content and all 5 services (player, knowlg, lern, cert, sync-tool) are reading through the CDN instead of the raw blob URL, nothing needs anonymous access anymore — the CDN authenticates to storage on the backend using its own identity, and the public internet only ever talks to the CDN, never to blob storage directly. Once that's validated, we can safely flip this switch off.

Important detail: This does not need the upload fix to happen first — uploads were never anonymous (they already use signed SAS tokens), so this control is independent of the write path.

---
4. Public access level should be Private for blob containers (39 resources)

What it checks: Each individual container can independently be set to "Private," "Blob" (anonymous read of individual blobs), or "Container" (anonymous read + listing). This finding flags every container currently set to something other than Private.

Why it's the biggest finding in the whole report: 39 containers — more than any other single finding — are currently configured to allow anonymous public reads. This is the largest attack surface identified across the entire 161-finding report.

Why it's a blocker: These are exactly the containers serving actual learner content — videos, course material, images — through the public URLs baked into player/knowlg/lern/cert. A Private Endpoint wouldn't fix this either, because a Private Endpoint only helps things inside your VNet reach storage privately — a learner's browser sitting on the public internet gets nothing from that.

How we're fixing it: Same CDN work as #3 above — once the CDN is the only thing serving these containers to the public, flip each one to Private. This closes the single largest finding in the report.

---
5–8. The four "network access" controls (Default network access rule, Public network access disabled, Storage account public access disallowed, Storage accounts should restrict network access) — 4 + 6 + 6 + 4 = 20 resources

What they check: These are 4 separately-named CSPM controls, but they all check essentially the same underlying thing — whether the storage account's network firewall is set to deny traffic from the public internet by default, with explicit exceptions only for what you've allowed in.

Why they're flagged together: Right now, the storage accounts accept connections from any network by default — no firewall at the network layer at all. Anyone who discovers the storage account's hostname can probe it.

Why this is the hardest one to fix: Unlike #3/#4 above, this affects both reads and writes:
- Reads — browsers loading public content currently connect directly to blob storage's public endpoint. If we deny public network access, that connection gets refused outright, regardless of whether the content itself is still "public" at the container level.
- Writes (confirmed in code) — when someone uploads content, the browser gets a signed SAS URL and PUTs the file directly to blob storage from their own machine, also over the public network path. A network firewall sits below the authentication layer — a perfectly valid, correctly-signed SAS token doesn't matter if the network rule rejects the client's IP before the signature is even checked. If you flip this without fixing uploads first, content authoring breaks, not just content viewing.

How we're fixing it: This needs both pieces in place first:
1. Reads already moved behind a CDN (same work as #3/#4).
2. Uploads switched from "browser PUTs directly to blob storage" to "browser sends the file to our backend API, and the backend writes it to storage from inside the network" — since the backend is already inside the VNet and already has the internal access path from prep step #2.

Only once both are done and validated can we flip the storage account's network default to "Deny" — at which point all 4 of these controls close together, since they're really the same underlying setting viewed through 4 different compliance-rule names.

---
Summary of what's independent vs. sequenced: #1 (HTTP(S) review) and the prep step are the only two pieces with zero dependencies — everything else is gated behind building the CDN (unlocks #3/#4, the biggest win) and then additionally the upload rework (unlocks #5–8, the hardest and most dependent group).
