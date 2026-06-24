# GCP Script Optimization — Flow Plan

Codename: **`gcp-no-keys`**

---

## Before (current state)

```
                ┌────────────────────────┐
                │   Operator (Owner)     │
                │   runs locally         │
                └──────────┬─────────────┘
                           │ owner creds
                           ▼
              ┌──────────────────────────┐
              │   tofu apply             │
              │   (modules/service-      │
              │   account)               │
              └──────────┬───────────────┘
                         │
                         ├─► google_service_account_key
                         │       │
                         │       ▼
                         │   sa-keys/<env>.json  ◄── KEY ON DISK
                         │       │
                         │       ▼
                         │   GCS bucket upload   ◄── KEY IN BUCKET
                         │
                         ├─► roles/storage.admin (PROJECT-WIDE)
                         │
                         └─► global-cloud-values.yaml
                                 │
                                 ├─ cloud_storage_secret_key  ◄── KEY IN YAML
                                 └─ cloud_storage_private_key_id
                                         │
                                         ▼
                                 ┌───────────────┐
                                 │ rclone.conf   │
                                 │ key = <KEY>   │ ◄── KEY IN CONFIG
                                 └───────────────┘

GitHub Actions:
  GCP_SA_KEY (JSON in repo secret) ◄── STATIC LONG-LIVED CREDENTIAL
```

### Problems
- 4 places where SA key lives (disk / bucket / yaml / rclone)
- `roles/storage.admin` at project scope — over-broad
- Public buckets granted `objectAdmin@allUsers` — anyone can write
- Storage module mandatory — cannot reuse existing buckets
- GH secret holds static JSON key — leak = full compromise

---

## After (target state)

```
              ┌─────────────────────────────────┐
              │   Operator (Owner) — ONE TIME   │
              │   gcp-setup-infra-sa.sh         │
              │   gcp-setup-deploy-sa.sh        │
              └─────────────┬───────────────────┘
                            │ creates
                            ▼
                  ┌─────────────────────┐
                  │  WI Pool + GH OIDC  │
                  │  Provider           │
                  │  (pinned to repo)   │
                  └──────────┬──────────┘
                             │
                ┌────────────┴─────────────┐
                ▼                          ▼
        ┌──────────────┐            ┌──────────────┐
        │  INFRA SA    │            │  DEPLOY SA   │
        │  installer_  │            │  cluster-    │
        │  role        │            │  scoped      │
        │  (no keys)   │            │  only        │
        └──────┬───────┘            └──────┬───────┘
               │                           │
        ┌──────┴────────┐         ┌────────┴────────┐
        │ Phase 1: GH   │         │ Phase 2: GH     │
        │ Action runs   │         │ Action runs     │
        │ tofu apply    │         │ helm + kubectl  │
        └──────┬────────┘         └────────┬────────┘
               │                           │
               ▼                           ▼
       creates infra:               deploys workloads:
       - VPC                        - helm releases
       - GKE                        - configmaps
       - buckets (or skip)          - secrets
       - workload-identity SA       - reads private bucket
                                        only
       NO KEY GENERATED
       Pods use Workload Identity
       (k8s SA -> GCP SA via annotation)


GitHub Actions secrets:
  GCP_PROJECT_ID
  GCP_WORKLOAD_IDENTITY_PROVIDER   ◄── provider path, NOT a key
  GCP_INFRA_SA_EMAIL                ◄── identity, NOT a key
  GCP_DEPLOY_SA_EMAIL               ◄── identity, NOT a key
  ANSIBLE_VAULT_PASSWORD
```

---

## Storage module — dual mode

```
skip_storage_module: false         skip_storage_module: true
─────────────────────────         ─────────────────────────

┌──────────────┐                  ┌──────────────────────┐
│ storage      │                  │ existing             │
│ module       │                  │ global-cloud-        │
│ creates      │                  │ values.yaml          │
│ buckets      │                  │ (from private repo)  │
└──────┬───────┘                  └──────────┬───────────┘
       │                                     │
       │ outputs                             │ try(yamldecode())
       ▼                                     ▼
┌─────────────────────────────────────────────────────┐
│  workload-identity / output-file / upload-files     │
│  read bucket names via ternary on skip flag         │
└─────────────────────────────────────────────────────┘
```

---

## Auth flow at runtime

```
GitHub Actions runner
   │
   │ requests OIDC token
   ▼
GitHub OIDC issuer
   │
   │ signed JWT (short-lived)
   ▼
google-github-actions/auth@v2
   │
   │ presents JWT to GCP STS
   ▼
GCP STS
   │ validates:
   │   - issuer == github
   │   - assertion.repository pinned
   │   - principalSet matches
   │
   │ returns federated access token
   ▼
SA impersonation (infra OR deploy)
   │
   │ ADC populated for tofu/gcloud/rclone/kubectl
   ▼
GCP API calls — scoped to SA's role only
```

---

## What we achieve

| Concern | Before | After |
|---|---|---|
| SA JSON keys generated | yes (4 copies) | **none** |
| GH secret type | static JSON key | identity ref (no secret value) |
| Token lifetime | infinite | 1 hour |
| `roles/storage.admin` scope | project | dropped — bucket-scope custom role |
| Public bucket write | `objectAdmin@allUsers` | `objectViewer@allUsers` |
| Storage reuse | no | flag-controlled |
| Phase isolation | one credential does both | infra SA ≠ deploy SA |
| Deploy SA cluster scope | n/a | single cluster (IAM condition) |
| Org-policy reinforcement | not enforceable | `disableServiceAccountKeyCreation` works |
| Blast radius if SA leaked | full project | scoped role only |
| Blast radius if GH secret leaked | full project takeover | nothing — no secret value |

---

## Hard guarantees

1. `installer_role` excludes all `iam.serviceAccountKeys.*` — cannot create keys.
2. WIF provider `attribute-condition` pins to repo — other repos cannot impersonate.
3. Deploy SA bound via IAM condition `resource.name == cluster` — scoped to one cluster.
4. Public buckets read-only for `allUsers`.
5. Even if a future Tofu PR reintroduces `google_service_account_key`, apply fails with `permissionDenied`.
