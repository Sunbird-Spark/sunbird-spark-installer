# Azure CSPM BLOCKER Findings — Comprehensive Fix Plan

Covers the 65 "real blocker" resources (7 controls) from the CSPM fix plan — the
findings that will break live functionality unless a bigger architecture change
happens first. This is a design doc, not an implementation — nothing below has been
built yet.

## Grounding: how reads and writes actually work today

Confirmed by reading the actual code (not assumed from the CSPM report) — this is
what every "why/how" below is based on.

### Reads
`object_storage_endpoint` (`{storage_account}.blob.core.windows.net`) and
`public_container_name` are baked directly into config for **5 separate services**:

- `player` — `helmcharts/edbb/charts/player/configs/env.yaml:26`
  (`SUNBIRD_CLOUD_STORAGE_URLS`)
- `knowlg` — `helmcharts/knowledgebb/charts/knowlg/configs/application.conf:265,390-408`
- `lern` — `helmcharts/learnbb/charts/lern/configs/env.yaml:61-69,166-171,196`
- `cert` — `helmcharts/learnbb/charts/cert/configs/env.yaml:3-22`
- `sync-tool` — same pattern as knowlg

All of them point straight at the raw public blob URL and depend on the containers
being anonymously readable.

### Writes
Kong routes 4 upload endpoints to backend services, which mint a SAS token
server-side; the browser then PUTs directly to blob storage with that token:

- `getContentUploadUrl` → `knowledge-mw-service` (`kong-apis.yaml:1116-1119`)
- `uploadUrlAsset`, `uploadUrlContentV2/V3` → `knowlg-service` (`kong-apis.yaml:4798-4800,7186-7188,7204-7206`)
- `getFileUploadUrls` → `ml-core-service` (`kong-apis.yaml:6327-6329`)

The SAS is **AAD user-delegation based, not account-key**:
`storage/main.tf:43` sets `shared_access_key_enabled = false`, and
`workload-identity/main.tf:56-78` grants the pods' managed identity
`generateUserDelegationKey` + `Storage Blob Data Contributor`.

**This matters:** a valid SAS token does not bypass a network ACL. If the storage
firewall denies the browser's IP, the signed URL is irrelevant — the PUT still fails.
Fixing auth (SAS, already done) and fixing network access (not done) are two
different problems — uploads are never anonymous, so they're unaffected by the
account's public-blob-access setting, only by the network ACL.

### Internal (AKS → storage) traffic
`opentofu/azure/modules/network/main.tf:64` sets `service_endpoints =
["Microsoft.Sql", "Microsoft.Storage"]` on the AKS subnet, but **only on the branch
where Terraform creates the VNet** (`skip_network_module: false`). The "reuse an
existing VNet" branch (`skip_network_module: true` — likely what real environments
like `ed-dev`/`ed-sandbox` actually use) never configures or verifies this. Real gap,
independent of everything else in this doc.

**Correction to the original CSPM plan doc's framing:** it cites the Cognitive
Services account's VNet Service Endpoint rule as a working precedent, but that
protection exists live in Azure, not in this repo's Terraform — there is no
VNet-rule-restricted resource anywhere in this codebase to copy. Any implementation
here is net-new.

**Why the `skip_network_module: true` gap isn't fixed in Terraform:** that branch
deliberately uses a read-only `data "azurerm_subnet"` block (`network/main.tf:35-40`)
to reference a subnet that already exists outside this repo. Service endpoints can
only be set by *fully owning* a subnet via an `azurerm_subnet` resource block —
switching to one just to add this setting would make Terraform start enforcing every
other property of that subnet too (NSG associations, delegations, etc. — unknown and
undeclared here), risking it silently reverting real configuration it was never told
about. Fixed instead via `cspm-fixes/enable-storage-service-endpoint.sh`, a targeted
`az network vnet subnet update` that touches only the service endpoint list.

## Key insight that reorders priority

The 6 storage-related controls do **not** all depend on the same fix. They split
into two groups with different, independent dependencies:

- **Group B (anonymous-access controls, 41 resources)** only depends on reads being
  moved off raw public blob URLs (Phase 2 below). Uploads are irrelevant here — they
  were never anonymous.
- **Group A (network-ACL controls, 20 resources)** depends on **both** reads *and*
  writes being moved off the public network path (Phase 2 **and** Phase 3).

This means Group B — which includes the single biggest finding in the whole
161-finding report (39 public containers) — can close as soon as Phase 2 ships,
**without waiting for the upload rework**. That's a materially faster path to
closing the highest-impact finding than treating all 61 resources as one blocked
unit.

## Every control: why, how, when it closes, and where the fix actually lives

Every fix below is classified by **scope** — this matters because our Azure account
is already running, but this repo is also what every *future* deployer uses to stand
up their own Azure account from scratch. A fix only prevents the problem for new
deployers if it's a change to this repo's Terraform; a fix applied only via `az` CLI
against our live account fixes *us* today but does nothing for the next org that
deploys this repo.

- **Code (Terraform)** — the fix is a change to a module in `opentofu/azure/modules/`.
  This protects every future deployer automatically (they get the fixed default the
  moment they run `install.sh`), **and** it must still be applied to our already-
  running account via `terragrunt apply` — writing the code alone does not change
  what's live until that runs.
- **Account-only (script/manual)** — the fix only exists as a one-time action against
  our specific live resources (`az` CLI, portal). It does not change this repo's
  behavior, so a new deployer is not protected and could recreate the same problem if
  they set up similar infrastructure by hand the same way.

| # | Control | Resources | Why it's a blocker | How we're fixing it | Scope | Closes after |
|---|---|---|---|---|---|---|
| 1 | **HTTP(S) access from the Internet should be restricted** | 4 | Flags NSGs allowing HTTP/HTTPS from any IP — but the public ingress is *supposed* to be open to learners, so this needs a human to separate "ingress, leave alone" from "other NSG, actually too broad," not a bulk flip | Manual, independent NSG-by-NSG review (not the public ingress). No architecture dependency. | **Account-only.** Confirmed zero NSG resources exist anywhere in this repo's Terraform — these NSGs were created by hand, outside the codebase. Fixing them via `az` CLI does not change what a new deployer gets. If we want to actually prevent recurrence, that requires a separate decision: document secure NSG defaults in `private-repo-setup/README.md` for anyone setting up a similar ops/runner VM, or bring that VM under Terraform with secure defaults baked in (a bigger, separate project — not done here). | **Immediately** — no dependency on anything else in this doc |
| 2 | *(prep, not a control)* AKS↔storage internal access | — | Backend services (knowlg, lern, cert) need to keep reading/writing storage once the network gets locked down | **Done, 2 parts.** Storage side: `network_rules` added to `storage/main.tf` (default stays `Allow`, AKS subnet pre-registered as an exception) — plumbed through `storage/variables.tf` and `_common/storage.hcl`. Subnet side (`skip_network_module: true` case): a Terraform fix isn't safe here (see note below), so `cspm-fixes/enable-storage-service-endpoint.sh` covers it instead — reads the environment's `global-values.yaml`, no-ops on `skip_network_module: false` (Terraform already handles it), otherwise checks/adds the `Microsoft.Storage` endpoint via `az`, preserving any existing endpoints. | **Storage side: Code.** Protects every future deployer automatically; still needs `terragrunt apply` against the live account. **Subnet side: one-time script**, not wired into `install.sh` — has to be run per environment. | **Immediately** — zero behavior change, no dependency |
| 3 | **Allow Blob Anonymous Access should be Disabled** | 2 | Account-level switch that permits any container to be made public at all — broader than any single container's setting | Build the CDN/Front Door in front of the public container (Phase 2), migrate the 5 consuming services to the CDN hostname, validate, **then** disable this account-wide | **Code.** The storage account resource and the services' config both live in this repo; once the CDN module and migrated config are the new default, every future deployer gets a CDN-fronted, non-anonymous setup from day one. Still needs applying/rolling out to our live account, not just writing the code. | After **Phase 2 (reads via CDN)** only |
| 4 | **Public access level should be Private for blob containers** | 39 | The single largest finding in the report — 39 containers currently allow anonymous public read | Same as above: once the CDN is confirmed as the only thing reading from these containers, flip each container's access type to Private | **Code.** `container_access_type` is set in `storage/main.tf:92` today (`"blob"`) — changing this default to `"private"` once the CDN exists fixes it for every future deployer, not just us. | After **Phase 2 (reads via CDN)** only |
| 5 | **Default network access rule should be set to deny** | 4 | Storage accounts accept requests from any network by default | Flip the account's default network action to `Deny`, with the AKS-subnet exception from prep step #2 already in place | **Code.** Same `network_rules` block added in step 2, `default_action` changed from `Allow` to `Deny` — a default every future deployer inherits. | After **Phase 2 AND Phase 3** (reads via CDN **and** writes via backend-mediated upload) |
| 6 | **Public network access should be disabled** | 6 | Same category as #5, turns off public reachability at the account level entirely | Same fix as #5 — one account-level setting closes both controls together | **Code.** Same change as #5. | After **Phase 2 AND Phase 3** |
| 7 | **Storage account public access should be disallowed** | 6 | Stronger account-level toggle, prevents any container from ever being made public again, even by accident later | Same fix as #5/#6 | **Code.** Same change as #5. | After **Phase 2 AND Phase 3** |
| 8 | **Storage accounts should restrict network access** | 4 | Same control family as #5 — flags accounts with no network restriction configured at all | Same fix as #5/#6/#7 | **Code.** Same change as #5. | After **Phase 2 AND Phase 3** |

(8 rows because "Default network access rule," "Public network access disabled,"
"Storage account public access disallowed," and "Storage accounts should restrict
network access" are 4 separate CSPM controls that all close via the **same single
Terraform change** — flipping the account's network default action to `Deny`.)

**Net effect of the scope column:** 7 of the 8 rows are Terraform changes — once
built, they protect every future deployer by default, and we additionally need to
run `terragrunt apply`/roll out the config to make our own already-running account
match. Only row #1 (the NSG review) is account-only with no code equivalent, since
there's no NSG resource in this repo to fix in the first place — for that one, "fix
it for us" and "fix it for everyone" are two genuinely different tasks, and only the
`az` CLI review closes it for us today.

## The phases that unlock the table above

### Phase 1 — lock down internal traffic (no behavior change)
Row #2 above. Zero risk. Start immediately alongside the HTTP(S) NSG review.

### Phase 2 — reads: CDN / Front Door in front of the public container
Stand up a CDN (or Azure Front Door) in front of the public blob container, then
migrate all 5 services (`player`, `knowlg`, `lern`, `cert`, `sync-tool`) from the raw
blob URL to the CDN hostname. Unlocks rows #3 and #4 (41 resources) once validated.
Real engineering effort:
- Config migration across 5 services.
- **Data migration, not just config**: content URLs already stored in the database
  reference the old blob URLs — needs a redirect/alias strategy or a bulk rewrite.

### Phase 3 — writes: replace direct-to-blob SAS uploads with backend-mediated uploads
Recommended: browser → Kong → `knowlg-service`/`ml-core-service` (already inside the
VNet, already holds `Storage Blob Data Contributor` via workload identity) → service
writes to blob over the now-allowed internal path. Unlocks rows #5–#8 (20 resources),
*combined with* Phase 2 — both reads and writes must be off the public network path
before the account-level network deny can safely flip.

Considered and **not** recommended as the default: making a CDN/Front Door proxy PUT
requests through to a private storage origin (e.g. Front Door Premium + Private
Link). Technically possible, but large-file-upload reliability/limits through that
path need explicit verification before relying on it — backend-mediated upload is
the better-established, lower-risk default.

## Immediate action items (do these first, before any design decision)

1. **HTTP(S) NSG review** (row #1) — tooling built: `cspm-fixes/review-public-http-nsgs.sh`.
   Still needs someone with real `az` access to run it against the live account.
2. **Phase 1 groundwork** (row #2) — **done.** `network_rules` added to the storage
   module (storage-side Terraform) plus `cspm-fixes/enable-storage-service-endpoint.sh`
   (subnet-side, for the `skip_network_module: true` case). Both still need to be
   actually applied/run against the real environment — code existing isn't the same
   as it being live.

Everything else in the table is correctly sequenced behind Phase 2 and/or Phase 3 —
do not skip ahead on those, since doing so breaks content loading or uploads for
every learner.

## Open questions to resolve before Phase 2/3 implementation

- Does the real `ed-dev`/`ed-sandbox` AKS subnet already have `Microsoft.Storage`
  service endpoint enabled live, or is this new work? Needs an `az network vnet
  subnet show` check against the live subnet.
- ~~CDN vs. Azure Front Door (Standard vs. Premium) — cost/capability tradeoff not
  yet decided.~~ **Resolved:** Azure Front Door Premium. Classic Azure CDN is
  retiring (no new profiles since Aug 2025). Confirmed via Microsoft Q&A that
  `Microsoft.Cdn/profiles` isn't a valid storage network-rule exception, so Front
  Door Standard cannot reach a fully-denied storage account without Private Link —
  only Premium supports Private Link. See `azure-blocker-implementation-steps.md`
  Step 3 for the full pricing/capability comparison.
- Scope of the content-URL data migration (how many stored records reference the old
  blob URL pattern, and whether a redirect at the old hostname is feasible vs. a hard
  cutover).
- Confirm Front Door's non-GET proxy behavior/limits if Phase 3's backend-mediated
  approach is ever reconsidered in favor of a CDN-proxied write path.
