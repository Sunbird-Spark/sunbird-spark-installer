# cspm-fixes

One-time fixes for CSPM findings that can't be closed through this repo's OpenTofu,
because the affected resources are created outside this repo's Terraform state
entirely. Not part of `install.sh` — these are standalone tools run manually.

## review-public-http-nsgs.sh

Covers: "HTTP(S) access from the Internet should be restricted" (4 resources, part
of the BLOCKER findings in `azure-blocker-fixes.md`, row #1).

**Why this is a script, not a Terraform fix:** there are zero NSG resources anywhere
in this repo's Terraform — these NSGs were created by hand, outside the codebase
(likely alongside standalone ops/CI VMs). See `azure-blocker-fixes.md` for the full
scope discussion (code-level vs. account-only fixes).

**Working:**
1. Auto-discovers every NSG in your subscription (or a specific resource group, via
   `--resource-group`) — no need to list names manually.
2. Skips any NSG you've told it to via `--ignore <name>` (pass it once per NSG you
   want left alone — most importantly, the NSG fronting your public ingress, which
   is *supposed* to allow everyone in on port 443).
3. For everything else, lists every inbound rule and flags any that allow port 80
   and/or 443 from `*`/`Internet`/`0.0.0.0/0`.
4. Dry run by default — only reports what it found. With `--apply`, it will delete a
   flagged rule, but only after you type the NSG's name to confirm, one NSG at a
   time — never in bulk, since nothing here can verify that no other legitimate
   traffic depends on that open rule.

**Why it doesn't auto-detect the ingress NSG for you:** tracing "which NSG actually
backs the ingress's public IP" through the load balancer/NIC chain is fragile and
depends on the specific AKS networking setup (CNI plugin, load balancer SKU, whether
AKS attaches a per-NIC NSG at all). Telling the script explicitly via `--ignore` is
more reliable than risking it guessing wrong.

### Setup

1. `az login` and `az account set --subscription <subscription-id>`.
2. `jq` on your PATH.
3. Find the name of the NSG that fronts your public ingress (e.g. via the Azure
   portal, or `az network nsg list` and cross-referencing with your ingress's
   public IP/load balancer).

### Usage

- List out the resource group if necessary `RESOURCE_GROUP=""` in the `review-public-http-nsgs.sh`

Dry run, scanning the whole subscription:

```bash
./review-public-http-nsgs.sh --ignore <your-ingress-nsg-name>
```
Multiple NSGs to leave alone — repeat `--ignore`:

```bash
./review-public-http-nsgs.sh --ignore nsg-one --ignore nsg-two
```

Scoped to one resource group:

```bash
./review-public-http-nsgs.sh --resource-group ed-coss --ignore <your-ingress-nsg-name>
```

Actually remove the flagged rules (prompts per NSG):

```bash
./review-public-http-nsgs.sh --ignore <your-ingress-nsg-name> --apply
```

If you run it with no `--ignore` at all, it prints a warning first — if your
ingress NSG isn't excluded and you re-run with `--apply`, it would remove the
ingress's own public rule and take the platform offline.
