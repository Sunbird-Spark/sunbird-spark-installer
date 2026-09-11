# TLS certificate automation: moving from certbot cronjob to cert-manager

## Current setup (as of today)

TLS for the public domain (e.g. `test.sunbirded.org`) is handled by a hand-rolled
in-cluster CronJob running `certbot`, plus a manual bootstrap step:

1. **First-ever cert for a new domain**: done manually, before any cluster/nginx
   exists to answer a challenge. Operator runs
   `certbot certonly --manual --preferred-challenges dns -d <domain>` on their own
   machine, certbot prints a TXT record value, operator manually adds that TXT
   record in GoDaddy, waits, certbot confirms and outputs a cert + key.
2. Operator manually pastes that cert/key into `global-values.yaml`
   (`proxy_private_key` / `proxy_certificate`), which Helm renders into the
   `nginx-public-ingress` Secret at install time.
3. **Ongoing renewal**: an in-cluster CronJob (`helmcharts/edbb/charts/nginx-public-ingress/templates/cronjob.yaml`)
   runs on a schedule. It temporarily takes over the nginx Service's selector,
   runs `certbot certonly --standalone` (HTTP-01, no DNS step needed at this
   point since nginx already exists), then `kubectl patch`es the renewed
   cert/key straight into the live Secret and restarts nginx.
4. **The catch**: `global-values.yaml`'s static `proxy_certificate`/`proxy_private_key`
   are *also* rendered into that same Secret by the Helm chart itself. So the
   next `helm upgrade edbb` — for any reason, not just cert-related — overwrites
   whatever the cronjob just renewed, reverting to the static (possibly
   stale/expired) value in `global-values.yaml`. Today this is worked around by
   the operator manually copying the cronjob's renewed keys back into
   `global-values.yaml` every time it renews, so the next `helm upgrade` doesn't
   clobber it. This is a real, recurring manual chore, and a real correctness
   risk if it's ever forgotten.

## Why move to cert-manager

cert-manager is the standard, widely-used Kubernetes-native certificate
automation tool. Moving to it removes every manual step above, permanently:

- No more manual DNS-01/TXT record step, not even for the first-ever
  certificate on a brand new domain.
- No more pasting cert/key values into `global-values.yaml`, ever.
- No more manual copy-back after every renewal.
- No more risk of `helm upgrade` silently reverting to a stale static cert.
- Automatic renewal ~30 days before expiry, with no cronjob, no cross-file
  manual sync step, no human in the loop at all once it's set up.

## How it works (architecture)

cert-manager's `Certificate`/`ClusterIssuer` CRDs, once created, own the TLS
Secret (`nginx-public-ingress`) directly and permanently. Getting there needed
solving one real architectural gap: cert-manager's standard HTTP-01 validation
(same challenge type the existing certbot cronjob already uses) requires an
actual Kubernetes Ingress controller reconciling ephemeral, per-challenge
`Ingress` objects — this repo's `nginx-public-ingress` is a hand-written
Deployment, not a real ingress controller, so it can't do that on its own.

The fix: add a **second, small, internal-only** ingress-nginx controller,
used *exclusively* to satisfy that one requirement.

```
Let's Encrypt validator
        │  GET http://<domain>/.well-known/acme-challenge/<token>
        ▼
nginx-public-ingress (public IP, unchanged)
        │  new static route: /.well-known/acme-challenge/ →
        ▼
ingress-nginx-controller (internal ClusterIP only, no public IP of its own)
        │  reconciles cert-manager's ephemeral per-challenge Ingress
        ▼
cert-manager's temporary challenge-solver pod
        │  confirms domain ownership
        ▼
cert-manager writes the issued cert/key straight into the
nginx-public-ingress Secret. Reloader (already running in-cluster) detects
the change and restarts nginx automatically.
```

`nginx-public-ingress` stays the only thing with a real public IP/DNS record
— nothing about the platform's actual internet-facing entrypoint changes.

## Security posture

- **No new public attack surface.** The internal ingress-nginx controller is
  `ClusterIP` only — it has no LoadBalancer/public IP of its own, and can only
  ever receive traffic that `nginx-public-ingress` explicitly forwards to it.
  The domain's public IP and DNS record are unchanged.
- **NetworkPolicy-restricted further.** On top of being ClusterIP-only, a
  `NetworkPolicy` (`acme-solver-networkpolicy.yaml`) restricts it to only
  accept traffic from `nginx-public-ingress` pods specifically — nothing else
  in the cluster can reach it, matching the same least-privilege pattern
  already used for Kong's admin API NetworkPolicy.
- **Least-privilege RBAC.** The one new piece of RBAC this adds (a `wait-for-cert`
  init container, needed to solve a bootstrap ordering problem — see below) is
  scoped to `get` on exactly one named Secret. No `list`/`watch`, no wildcard
  resource names.
- **No cert/key material in git or `global-values.yaml` anymore.** Removes a
  real class of exposure: private key material previously had to pass through
  an operator's local machine and a values file at all. cert-manager generates
  and stores the key material directly in the cluster, never leaving it.
- **HTTP-01 challenge traffic is inherently public/unauthenticated by
  design** — that's how ACME domain validation works for anyone (Let's
  Encrypt, this repo's existing certbot flow, or cert-manager) — this isn't a
  new weakening, it's the same trust model the current mechanism already
  relies on.

One real gap found and fixed during implementation: `tls.crt`/`tls.key` are
`subPath`-mounted into the nginx pod, which requires both keys to already
exist in the Secret. On a brand-new domain, cert-manager hasn't issued
anything yet at first install — without a fix, the nginx pod would
crash-loop before it could even serve the ACME challenge cert-manager needs
routed through it (a chicken-and-egg deadlock). Fixed with a small
`wait-for-cert` init container that blocks pod startup until both keys
appear in the Secret.

## Rollout safety

This is entirely **opt-in** via a new `global.cert_manager_ssl` flag,
defaulting to `false`:

- Existing installs: **zero behavior change.** Nothing is different unless
  this flag is explicitly set to `true`.
- Mutually exclusive with the existing `lets_encrypt_ssl` flag — if both are
  set, `cert_manager_ssl` wins and the old certbot CronJob is skipped, so the
  two mechanisms never fight over the same Secret.
- cert-manager and the internal ingress-nginx controller are themselves
  separate Helm dependencies, both `enabled: false` by default — they don't
  even get installed unless explicitly turned on.

## Testing performed

Verified in a fully isolated standalone test (own namespace, own Helm
release names, own LoadBalancer IP) on the `ed-dev` cluster — zero impact on
the live, working `edbb` release or `test.sunbirded.org`:

- cert-manager installed cleanly, `ClusterIssuer` registered with Let's
  Encrypt successfully (`Ready: True`).
- `Certificate` → `CertificateRequest` → `Order` → `Challenge` all created
  correctly.
- Confirmed cert-manager's ingress-shim created the ephemeral solver
  `Ingress`, and the internal ingress-nginx controller picked it up and
  served the challenge correctly (`Presented challenge using HTTP-01
  challenge mechanism`).
- The only remaining step to see a fully issued certificate end-to-end is a
  real DNS A record for the test subdomain, confirming the whole chain up to
  that point works exactly as designed.
