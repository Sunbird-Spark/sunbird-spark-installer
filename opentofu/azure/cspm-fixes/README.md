# cspm-fixes

One-time fix for the CSPM "compute hygiene" SAFE findings from `opentofu/azure/azure-csm-fix-plan.md`
that could **not** be fixed through this repo's OpenTofu, because the affected VMs are
created outside this repo's Terraform state entirely (e.g. Jenkins, CI runners, other
standalone ops VMs).

This is not part of `install.sh` and does not run automatically. It's a standalone
tool you run manually, once, against your own existing VMs.

## What it fixes

| # | Control | Risk if misapplied |
|---|---|---|
| 1 | Disk Network Access should not allow public access from all networks | None — only affects the disk's snapshot/export endpoint, not the running VM |
| 2 | Internet-facing VMs should be protected with NSGs | Handled safely — see note below |
| 3 | System updates should be installed | Low — a patch can trigger a service restart |

**Not covered:** "Audit Linux machines allowing password-based SSH." Whether that's
safe depends on a human judgment call (do SSH keys already work for every admin on
that VM) that a script shouldn't make on its own — get it wrong and you lock
yourself out. Treat it as a manual step instead:

1. SSH into the VM.
2. Confirm `~/.ssh/authorized_keys` (and `/root/.ssh/authorized_keys`) is populated
   for every admin who needs access.
3. Only then set `PasswordAuthentication no` in `/etc/ssh/sshd_config` and restart
   `sshd` — one VM at a time, never in bulk.

### Note on the NSG fix (#2)

A brand-new Azure NSG is not "no rules = allow everything" — it carries a built-in
`DenyAllInBound` default for anything outside the VNet. Attaching an empty NSG to a
VM that currently has none would cut off its inbound traffic the instant it attaches.
To avoid that, the script creates the NSG with a temporary allow-all-inbound rule at
the same time it's attached, so nothing breaks immediately. It then prints a `TODO`
reminding you to replace that temporary rule with one scoped to only the ports the
VM actually needs — that tightening is a deliberate follow-up step, not something
this script decides on its own.

## Setup

1. Make sure you're authenticated to the right subscription:
   ```bash
   az login
   az account set --subscription <subscription-id>
   ```
2. `yq` (mikefarah/yq v4) must be on your PATH.
3. Edit `vms.yaml` in this folder: replace the placeholder entries with your actual
   VM names and resource groups. Every deployment of `sunbird-spark-installer` names
   its standalone VMs differently — nothing here is hardcoded.

## Usage

Dry run (default — prints what would change, makes no changes):

```bash
./fix-compute-hygiene.sh
```

Actually apply the fixes — either set `apply: true` in `vms.yaml`, or override it
for a single run without editing the file:

```bash
./fix-compute-hygiene.sh --apply
```

Force a dry run even if `vms.yaml` has `apply: true`:

```bash
./fix-compute-hygiene.sh --dry-run
```

Use a different config file:

```bash
./fix-compute-hygiene.sh --config /path/to/other-vms.yaml
```

The script is idempotent — re-running it skips anything already fixed (a disk
already `DenyAll`, a VM that already has an NSG attached). Step 3 (OS updates)
prompts you to type the VM's exact name to confirm before patching each one, since
patching can restart a service — run it in a maintenance window.
