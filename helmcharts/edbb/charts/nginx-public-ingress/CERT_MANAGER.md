# TLS certificate automation: moving from certbot cronjob to cert-manager

## Previous setup (removed)

Before cert-manager, TLS for the public domain (e.g. `test.sunbirded.org`) was handled by a
hand-rolled in-cluster CronJob running `certbot`, plus a manual bootstrap step. This mechanism
(the `lets_encrypt_ssl` flag, `templates/cronjob.yaml`, and the manual DNS-01 bootstrap below) has
since been fully removed now that cert-manager is proven out end-to-end -- kept here only as
historical context for why cert-manager was worth the migration:

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
(same challenge type the old certbot cronjob used) requires an
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
  scoped to `get`/`patch` on exactly one named Secret. No `list`/`watch`, no
  wildcard resource names.
- **No cert/key material in git or `global-values.yaml` anymore.** Removes a
  real class of exposure: private key material previously had to pass through
  an operator's local machine and a values file at all. cert-manager generates
  and stores the key material directly in the cluster, never leaving it.
- **HTTP-01 challenge traffic is inherently public/unauthenticated by
  design** — that's how ACME domain validation works for anyone (Let's
  Encrypt, this repo's old certbot flow, or cert-manager) — this isn't a
  new weakening, it's the same trust model the old mechanism already relied
  on.

Two real gaps found and fixed during implementation, both only surfaced via
live end-to-end testing:

- `tls.crt`/`tls.key` are `subPath`-mounted into the nginx pod, which
  requires both keys to already exist in the Secret. On a brand-new domain,
  cert-manager hasn't issued anything yet at first install. The first version
  of `wait-for-cert` just blocked pod startup until both keys appeared — but
  that's a deadlock, not a fix: cert-manager's HTTP-01 challenge needs this
  pod running to route the challenge through in the first place, so it can
  never succeed while the pod sits blocked waiting for it. Fixed by having
  `wait-for-cert` generate a throwaway self-signed bootstrap cert and patch it
  into the Secret when no cert exists yet, so nginx starts immediately and can
  serve the challenge. cert-manager overwrites the Secret with the real,
  ACME-issued cert once issuance succeeds, and Reloader (already running
  in-cluster) restarts nginx to pick it up.
- The static route added for the ACME challenge path
  (`^~ /.well-known/acme-challenge/`) was never actually reached — the
  existing catch-all `return 301 https://...` in `proxy-default.conf` is a
  bare directive directly in the `server` block, not inside a `location`.
  nginx evaluates that during the server-rewrite phase, which runs *before*
  location matching, so it fired unconditionally on every request regardless
  of location block order, redirecting the ACME validator instead of serving
  the challenge. Fixed by wrapping it in `location / { return 301 ...; }` so
  it's a real location directive and the more specific challenge location
  correctly takes precedence.

## Rollout safety

This is entirely **opt-in**, gated by three flags in the operator's own
`opentofu/<provider>/<env>/global-values.yaml` (not the shared
`helmcharts/edbb/values.yaml`), all defaulting to `false`/disabled:

```yaml
cert-manager:
  enabled: false
ingress-nginx:
  enabled: false
global:
  cert_manager_ssl: false
```

All three must be set together to actually enable automated TLS:
- `cert-manager.enabled` / `ingress-nginx.enabled` are the `condition:` flags
  on `edbb`'s own Helm dependencies (`Chart.yaml`) — install the two
  supporting subcharts.
- `global.cert_manager_ssl` gates this chart's own templates: it skips
  rendering the static `proxy_certificate`/`proxy_private_key` into the
  Secret, and creates the `ClusterIssuer`/`Certificate`.

Setting only one or two of the three doesn't work: e.g. `cert_manager_ssl:
true` alone creates a `Certificate`/`ClusterIssuer` with no controller
installed to service them, and skips the static cert render too, so nginx
would just wait on a certificate that never arrives.

- Existing installs: **zero behavior change.** With all three left at their
  defaults, the chart renders `proxy_certificate`/`proxy_private_key` from
  `global-values.yaml` into the Secret exactly as before -- the old
  `lets_encrypt_ssl`/certbot mechanism has been removed outright rather than
  kept as a second opt-in path, since cert-manager fully replaces it.

## Bringing your own certificate instead

Not everyone wants cert-manager -- if you already have your own certificate (e.g. from a
commercial CA) and don't want automated issuance/renewal, leave `cert-manager.enabled`,
`ingress-nginx.enabled`, and `global.cert_manager_ssl` all at their default `false`, and paste
your cert/key into `proxy_certificate`/`proxy_private_key` in `global-values.yaml` as always.
This is rendered straight into the `nginx-public-ingress` Secret on every install/upgrade --
no cert-manager, no cronjob, nothing else runs on this path. Renewal is entirely manual: get
the new cert/key from your own source, replace the values in `global-values.yaml`, re-run the
upgrade. This path is unrelated to cert-manager and unaffected by anything in this document.

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
- With a real DNS A record in place for the test subdomain
  (`dev.sunbirded.org`) and the two fixes above applied, the full chain
  completed end-to-end: the `Challenge` reached `valid`, the `Order` reached
  `valid`, and cert-manager wrote a real Let's Encrypt certificate into the
  Secret. Verified directly via `openssl x509 -noout -issuer -subject -dates`
  on the live Secret (`issuer=.../O=Let's Encrypt/CN=YR1`,
  `subject=/CN=dev.sunbirded.org`) and via `curl -v https://dev.sunbirded.org`
  from outside the cluster, showing `TLSv1.3` negotiated with that same
  certificate and `HTTP/1.1 200 OK`.
- Note specific to this standalone test setup (not a cert-manager issue): the
  test release inherited this chart's pre-existing `wait-for-keycloak`/
  `wait-for-kong`/`wait-for-player` init containers, which do bare-hostname
  checks that only resolve within the same namespace — since those services
  actually live in `sunbird`, not the test's own namespace, they'd hang
  forever. Patched out for the test release only (`kubectl patch` removing
  those 3 containers from the Deployment); not a change to the chart itself.
- Also specific to this standalone test setup: nginx's own upstream
  references to `kong`/`keycloak`/`player`/`monitoring-grafana` are bare
  hostnames, which only resolve within the same namespace. Since those
  services live in `sunbird`, not the test namespace, the test release's
  Secret content was live-patched to use namespace-qualified names
  (`kong.sunbird`, `keycloak.sunbird`, etc.) instead — a test-only Secret
  edit, not a chart change.
