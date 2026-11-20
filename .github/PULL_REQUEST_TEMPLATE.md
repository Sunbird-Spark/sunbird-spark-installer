## What changed

<!-- A sentence or two on the change itself. -->

**Touches:** <!-- OpenTofu modules / Helm charts / scripts / Dockerfiles / workflows / docs -->
**Providers affected:** <!-- Azure / AWS / GCP / all / none -->

## Why

Fixes #<!-- issue number -->

- [ ] I commented on the issue to say I was taking it

## How this was verified

- [ ] Static checks only — actionlint, shellcheck, hadolint, `tofu validate`
- [ ] Deployed to my own cloud account and verified the result
- [ ] Couldn't deploy — a maintainer will need to verify this

**If deployed:** which provider, environment name, and what you checked afterwards.

<!--
Be specific. "Works on my cluster" doesn't tell a reviewer whether you ran a fresh
install or an upgrade, or which addons were enabled. Redact subscription IDs,
account numbers and domains.
-->

## Resource impact

- [ ] No change to CPU, memory or disk requests or limits
- [ ] Requests or limits changed — stated below, and `INFRA_DETAILS.md` updated

<!--
The stack is sized to fit two 16 vCPU / 64 GB nodes with all addons enabled.
Say what the change costs so adopters aren't surprised at install time.
-->

## Anything a reviewer should look at closely

<!-- Tag the reviewer or repo owner. Leave blank if nothing stands out. -->

## Contribution Checklist

Link to your filled-in copy: <!-- paste here -->

## Before review

- [ ] Opened against the latest `v1.x.x` development branch, not `main`
- [ ] `actionlint` passes
- [ ] `shellcheck -S error` passes on the scripts you touched
- [ ] `hadolint --failure-threshold error` passes on any Dockerfile you touched
- [ ] `tofu validate` passes for every module you touched
- [ ] `tofu fmt` and `helm lint` are no worse than before <!-- both advisory today -->
- [ ] Documentation updated — README, `INFRA_DETAILS.md` or the provider READMEs, wherever this made them wrong

## Supply chain

- [ ] Not applicable — no workflow or Dockerfile changed
- [ ] Any action added or updated is pinned to a commit SHA with a version comment
- [ ] Workflow permissions are no broader than the job needs
- [ ] Any base image added or updated is digest-pinned

<!--
This repository is scored by OpenSSF Scorecard. Replacing a SHA pin with a tag,
or widening default permissions, lowers that score.
-->

## Secrets

- [ ] No cloud credentials, SSL private keys, API tokens, Ansible Vault passwords, kubeconfigs or account identifiers in the diff
- [ ] No values from a filled-in `global-values.yaml`

## Keycloak login theme

- [ ] Not applicable — no change under `scripts/keycloak-21.1.2/themes/`
- [ ] Changed, and `styles=css/login.css?v=…` bumped in `theme.properties`

<!--
Without the version bump, browsers serve the cached stylesheet and the change
won't appear. If you added a colour, font or template here, check it matches the
portal — see Cross-Repo Coupling in the portal's README.
-->

## Security

- [ ] This change touches authentication, Keycloak, Kong, certificates, secret handling, or what is exposed publicly

<!-- If checked, say what below and ask for a security-focused review. -->

<!--
Used AI tools? Declare them on the Contribution Checklist, and add an
`Assisted-by: <tool name>` commit trailer for substantially AI-generated code.
-->