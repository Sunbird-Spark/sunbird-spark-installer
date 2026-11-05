# cspm-fixes

Fixes for CSPM findings that can't be fully closed through this repo's OpenTofu
alone — the resource is created outside this repo's Terraform state entirely.
Scope is currently limited to Step 1 (HTTP(S) NSG review) — the broader Front
Door/upload-relay BLOCKER work is not being pursued.

## review-public-http-nsgs.sh

Covers: "HTTP(S) access from the Internet should be restricted" (4 resources, part
of the BLOCKER findings).

The same check also runs automatically on every `install.sh` run
(`opentofu/azure/template/install.sh:review_http_nsgs`) — use this standalone
script for a manual, one-time run instead (e.g. against an environment outside
the normal install flow, or to clean up findings right now without waiting for
the next deploy).

**Why this is a script, not a Terraform fix:** there are zero NSG resources
anywhere in this repo's Terraform — these NSGs were created by hand, outside the
codebase (likely alongside standalone ops/CI VMs).

**Working:**
1. Auto-discovers every NSG in your subscription (or a specific resource group,
   via `--resource-group`) — no need to list names manually.
2. Tries to auto-detect the real public ingress NSG by tracing its actual
   network path (ingress Service's public IP → Azure Public IP → Load Balancer
   → backend NIC → NSG). Requires `kubectl` already pointed at the right
   cluster and the ingress already deployed with a public IP assigned — if
   detection fails, pass `--ignore` yourself instead.
3. Skips any NSG you've told it to via `--ignore <name>` (pass it once per NSG
   you want left alone), in addition to whatever was auto-detected.
4. For everything else, lists every inbound rule and flags any that allow port
   80 and/or 443 from `*`/`Internet`/`0.0.0.0/0`.
5. Dry run by default — only reports what it found. With `--apply`, it will
   delete a flagged rule, but only after you type the NSG's name to confirm,
   one NSG at a time — never in bulk, since nothing here can verify that no
   other legitimate traffic depends on that open rule.

### Setup

1. `az login` and `az account set --subscription <subscription-id>`.
2. `jq` on your PATH.
3. If relying on auto-detection: `kubectl` pointed at the right cluster. If
   detection fails, find the name of the NSG that fronts your public ingress
   manually (e.g. via the Azure portal, or `az network nsg list`
   cross-referenced with your ingress's public IP/load balancer).

### Usage

Auto-detect the ingress, report only:
```bash
./review-public-http-nsgs.sh
```

Auto-detect the ingress, fix everything else:
```bash
./review-public-http-nsgs.sh --apply
```

Manual ingress name (if auto-detection fails or isn't available):
```bash
./review-public-http-nsgs.sh --ignore <your-ingress-nsg-name> --apply
```

Multiple NSGs to leave alone — repeat `--ignore`:
```bash
./review-public-http-nsgs.sh --ignore nsg-one --ignore nsg-two
```

Scoped to one resource group:
```bash
./review-public-http-nsgs.sh --resource-group ed-coss --ignore <your-ingress-nsg-name>
```

If auto-detection fails and you run with no `--ignore` at all, it prints a
warning first — if your ingress NSG isn't excluded and you re-run with
`--apply`, it would remove the ingress's own public rule and take the
platform offline.
