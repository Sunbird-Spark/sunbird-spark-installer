#!/usr/bin/env python3
"""
Apply spark keycloak chart realm.json diffs onto running Keycloak,
preserving all migrated user data + sessions in DB.

Source-of-truth: helmcharts/learnbb/charts/keycloak/configs/realm.json
(rendered through helm; pull rendered ConfigMap when running in cluster).

Strategy:
  1) PUT /admin/realms/<realm>          — replaces realm-level settings only.
                                           DB users/sessions/credentials untouched.
  2) For each client in new realm:
     - PUT /clients/{uuid} (keeps UUID + secret, replaces config)
     - DELETE all existing protocol-mappers, then POST new mappers without IDs
       (avoids duplicate mappers from UUID mismatch).
  3) For each new top-level auth flow:
     - POST flow + recursively create subflows + executions
     - POST authenticatorConfig referenced by executions
  4) Update required actions enabled-state if differs.
  5) NEVER touch /users.

Usage (inside cluster):
  python3 keycloak_apply_realm_reconcile.py \
    --keycloak-url http://keycloak.sunbird.svc.cluster.local:8080 \
    --admin-user admin --admin-pass "$KC_ADMIN_PASSWORD" \
    --realm sunbird \
    --new-realm-file /opt/keycloak/data/import/realm.json
"""
import json
import sys
import argparse
import urllib.request
import urllib.parse
import ssl

ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE


def req(method, url, token=None, data=None):
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    body = json.dumps(data).encode() if data is not None else None
    r = urllib.request.Request(url, data=body, method=method, headers=headers)
    try:
        with urllib.request.urlopen(r, context=ctx) as resp:
            txt = resp.read().decode()
            return resp.status, (json.loads(txt) if txt and txt.strip().startswith(("{", "[")) else txt)
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()


def form_post(url, fields):
    data = urllib.parse.urlencode(fields).encode()
    r = urllib.request.Request(url, data=data, method="POST")
    r.add_header("Content-Type", "application/x-www-form-urlencoded")
    with urllib.request.urlopen(r, context=ctx) as resp:
        return json.loads(resp.read().decode())


def detect_kc_base(url):
    """Probe whether Keycloak uses /auth/ prefix or root. Returns adjusted base URL."""
    candidates = [url.rstrip("/"), url.rstrip("/") + "/auth"]
    for cand in candidates:
        try:
            r = urllib.request.Request(f"{cand}/realms/master", method="GET")
            with urllib.request.urlopen(r, context=ctx, timeout=10) as resp:
                if resp.status == 200:
                    print(f"  Detected Keycloak base: {cand}")
                    return cand
        except Exception:
            continue
    raise RuntimeError(f"Could not reach Keycloak at {url} (tried with and without /auth prefix)")


def get_token(base, user, pwd):
    return form_post(
        f"{base}/realms/master/protocol/openid-connect/token",
        {"client_id": "admin-cli", "username": user, "password": pwd, "grant_type": "password"},
    )["access_token"]


def patch_realm(base, tok, new):
    """PUT realm-level config (skip arrays handled separately)."""
    SKIP = {"users", "clients", "clientScopes", "roles",
            "authenticationFlows", "authenticatorConfig",
            "components", "requiredActions",
            "identityProviders", "identityProviderMappers",
            "groups", "scopeMappings", "clientScopeMappings",
            "defaultRole"}
    payload = {k: v for k, v in new.items() if k not in SKIP}
    s, body = req("PUT", base, tok, payload)
    if s not in (200, 201, 204):
        print(f"  realm PUT FAILED: HTTP {s} body={str(body)[:400]}")
    else:
        print(f"  realm PUT: HTTP {s}  (fields={len(payload)})")


def update_client(base, tok, existing, new_client, flow_uuid_remap=None):
    """PUT client (preserve UUID + secret), then DELETE+RECREATE mappers.

    flow_uuid_remap: dict[old_uuid_from_realm.json -> current_uuid_in_keycloak]
                     used to fix authenticationFlowBindingOverrides.
    """
    cid = new_client["clientId"]
    merged = dict(new_client)
    merged["id"] = existing["id"]
    if "secret" in existing and merged.get("secret") == "**********":
        merged["secret"] = existing["secret"]
    # Strip mapper IDs to avoid mismatch on PUT
    merged["protocolMappers"] = []  # handled below via dedicated endpoint

    # Remap authenticationFlowBindingOverrides UUIDs to current Keycloak UUIDs
    afbo = merged.get("authenticationFlowBindingOverrides") or {}
    if afbo and flow_uuid_remap is not None:
        fixed = {}
        for k, v in afbo.items():
            if v in flow_uuid_remap:
                fixed[k] = flow_uuid_remap[v]
            else:
                # Flow UUID not resolvable -> drop binding (avoid 500)
                print(f"  {cid}: dropping flowBindingOverride {k}={v} (no current UUID)")
        merged["authenticationFlowBindingOverrides"] = fixed

    new_uris = merged.get("redirectUris", []) or []
    s, body = req("PUT", f"{base}/clients/{existing['id']}", tok, merged)
    if s not in (200, 201, 204):
        print(f"  {cid}: client PUT FAILED HTTP {s} body={str(body)[:400]}")
    else:
        print(f"  {cid}: client PUT HTTP {s}")

    # Verify by GET after PUT
    s2, after = req("GET", f"{base}/clients/{existing['id']}", tok)
    if isinstance(after, dict):
        cur_uris = set(after.get("redirectUris", []) or [])
        want_uris = set(new_uris)
        missing = want_uris - cur_uris
        if missing:
            print(f"  {cid}: WARNING redirectUris missing after PUT: {sorted(missing)}")
        else:
            print(f"  {cid}: redirectUris OK ({len(cur_uris)})")

    # Now sync protocolMappers via dedicated endpoint
    mep = f"{base}/clients/{existing['id']}/protocol-mappers/models"
    s, existing_mappers = req("GET", mep, tok)
    if isinstance(existing_mappers, list):
        for em in existing_mappers:
            ds, db = req("DELETE", f"{mep}/{em['id']}", tok)
            if ds not in (200, 204):
                print(f"    DEL mapper {em.get('name')}: HTTP {ds} body={str(db)[:200]}")
    expected = new_client.get("protocolMappers", []) or []
    posted_ok = 0
    for nm in expected:
        nm_clean = {k: v for k, v in nm.items() if k != "id"}
        s2, body = req("POST", mep, tok, nm_clean)
        if s2 not in (200, 201, 204):
            print(f"    POST mapper {nm.get('name')!r} ({nm.get('protocolMapper')}): HTTP {s2} body={str(body)[:300]}")
        else:
            posted_ok += 1
    # Verify by GET after
    s3, after_mappers = req("GET", mep, tok)
    after_names = sorted(m.get("name") for m in after_mappers) if isinstance(after_mappers, list) else []
    want_names = sorted(m.get("name") for m in expected)
    missing_names = sorted(set(want_names) - set(after_names))
    print(f"  {cid}: mappers POST ok={posted_ok}/{len(expected)} after={len(after_names)}")
    if missing_names:
        print(f"    MISSING mappers: {missing_names}")


def build_flow_uuid_remap(base, tok, new):
    """Map realm.json flow UUIDs -> current Keycloak flow UUIDs (by alias)."""
    new_flows = new.get("authenticationFlows", []) or []
    new_uuid_to_alias = {f["id"]: f["alias"] for f in new_flows if f.get("id")}
    s, current = req("GET", f"{base}/authentication/flows", tok)
    if not isinstance(current, list):
        return {}
    cur_alias_to_uuid = {f["alias"]: f["id"] for f in current}
    remap = {}
    for old_uuid, alias in new_uuid_to_alias.items():
        if alias in cur_alias_to_uuid:
            remap[old_uuid] = cur_alias_to_uuid[alias]
    return remap


def update_clients(base, tok, new, flow_uuid_remap=None):
    print("\n==> Updating clients...")
    s, existing_clients = req("GET", f"{base}/clients?max=200", tok)
    if not isinstance(existing_clients, list):
        print(f"  ERROR fetching clients: HTTP {s} body={str(existing_clients)[:400]}")
        return
    by_cid = {c["clientId"]: c for c in existing_clients}
    print(f"  fetched {len(by_cid)} existing clients")
    for c in new.get("clients", []):
        cid = c["clientId"]
        if cid not in by_cid:
            cnew = {k: v for k, v in c.items() if k != "id"}
            s2, body = req("POST", f"{base}/clients", tok, cnew)
            if s2 not in (200, 201, 204):
                print(f"  CREATE {cid}: HTTP {s2} body={str(body)[:300]}")
            else:
                print(f"  CREATE {cid}: HTTP {s2}")
            continue
        update_client(base, tok, by_cid[cid], c, flow_uuid_remap=flow_uuid_remap)


def create_authenticator_configs(base, tok, new_configs, existing_alias_map):
    """POST authenticatorConfig if alias missing. Returns updated alias_map."""
    for cfg in new_configs:
        if cfg["alias"] in existing_alias_map:
            continue
        body = {"alias": cfg["alias"], "config": cfg.get("config", {})}
        # POST to flow-level — but Keycloak puts it under flows. Use generic endpoint.
        s, resp = req("POST", f"{base}/authentication/config", tok, body)
        print(f"  authConfig {cfg['alias']}: HTTP {s}")
        existing_alias_map[cfg["alias"]] = cfg.get("id")
    return existing_alias_map


def create_flow_with_executions(base, tok, new_flows_by_alias, alias, top_level, existing_flow_aliases, ac_alias_map):
    """Recursively create flow + executions + subflows + authenticatorConfigs."""
    if alias in existing_flow_aliases:
        return
    flow = new_flows_by_alias.get(alias)
    if not flow:
        return

    if top_level:
        body = {
            "alias": alias,
            "description": flow.get("description", ""),
            "providerId": flow.get("providerId", "basic-flow"),
            "topLevel": True,
            "builtIn": False,
        }
        s, _ = req("POST", f"{base}/authentication/flows", tok, body)
        print(f"  flow {alias}: HTTP {s}")
        existing_flow_aliases.add(alias)

    # Iterate executions in priority order
    execs = sorted(flow.get("authenticationExecutions", []), key=lambda e: e.get("priority", 0))
    for ex in execs:
        if ex.get("authenticatorFlow") and ex.get("flowAlias"):
            sub_alias = ex["flowAlias"]
            # Create subflow attached under parent
            sub = new_flows_by_alias.get(sub_alias, {})
            body = {
                "alias": sub_alias,
                "type": "basic-flow",
                "provider": sub.get("providerId", "basic-flow"),
                "description": sub.get("description", ""),
            }
            s, _ = req("POST", f"{base}/authentication/flows/{urllib.parse.quote(alias)}/executions/flow",
                       tok, body)
            if s not in (200, 201):
                print(f"    subflow {sub_alias}: HTTP {s}")
            existing_flow_aliases.add(sub_alias)
            # Set requirement on the subflow execution
            set_execution_requirement(base, tok, alias, sub_alias, ex.get("requirement"))
            # Recurse to populate the subflow's executions
            create_flow_with_executions(base, tok, new_flows_by_alias, sub_alias, False,
                                        existing_flow_aliases, ac_alias_map)
        else:
            # Plain authenticator execution
            body = {"provider": ex["authenticator"]}
            s, _ = req("POST", f"{base}/authentication/flows/{urllib.parse.quote(alias)}/executions/execution",
                       tok, body)
            if s not in (200, 201):
                print(f"    exec {ex.get('authenticator')}: HTTP {s}")
            set_execution_requirement(base, tok, alias, ex["authenticator"], ex.get("requirement"))
            # Attach authenticatorConfig if specified
            if ex.get("authenticatorConfig"):
                attach_exec_config(base, tok, alias, ex["authenticator"], ex["authenticatorConfig"])


def set_execution_requirement(base, tok, flow_alias, exec_match, requirement):
    """Find execution under flow + PUT its requirement."""
    if not requirement:
        return
    s, execs = req("GET", f"{base}/authentication/flows/{urllib.parse.quote(flow_alias)}/executions", tok)
    if not isinstance(execs, list):
        return
    target = None
    for e in execs:
        if e.get("displayName") == exec_match or e.get("providerId") == exec_match \
                or e.get("authenticationFlow") and e.get("displayName", "").startswith(exec_match):
            target = e
            break
    if not target:
        return
    body = dict(target)
    body["requirement"] = requirement
    req("PUT", f"{base}/authentication/flows/{urllib.parse.quote(flow_alias)}/executions", tok, body)


def attach_exec_config(base, tok, flow_alias, authenticator, config_alias):
    """Find execution + POST authenticatorConfig as alias for that execution."""
    s, execs = req("GET", f"{base}/authentication/flows/{urllib.parse.quote(flow_alias)}/executions", tok)
    if not isinstance(execs, list):
        return
    for e in execs:
        if e.get("providerId") == authenticator:
            body = {"alias": config_alias, "config": {}}
            req("POST", f"{base}/authentication/executions/{e['id']}/config", tok, body)
            return


def create_new_flows(base, tok, new):
    print("\n==> Creating new auth flows...")
    s, existing_flows = req("GET", f"{base}/authentication/flows", tok)
    existing_aliases = {f["alias"] for f in existing_flows}
    new_flows_by_alias = {f["alias"]: f for f in new.get("authenticationFlows", [])}
    s, existing_ac = req("GET", f"{base}/authentication/config-description", tok)
    ac_alias_map = {}  # populated lazily

    # Top-level flows that don't exist yet (skip built-ins)
    for alias, flow in new_flows_by_alias.items():
        if not flow.get("topLevel"):
            continue
        if flow.get("builtIn"):
            continue
        if alias in existing_aliases:
            continue
        create_flow_with_executions(base, tok, new_flows_by_alias, alias, True,
                                    existing_aliases, ac_alias_map)


def update_required_actions(base, tok, new):
    print("\n==> Updating required actions...")
    s, existing_ra = req("GET", f"{base}/authentication/required-actions", tok)
    existing_map = {r["alias"]: r for r in existing_ra}
    for ra in new.get("requiredActions", []):
        cur = existing_map.get(ra["alias"])
        if not cur:
            continue
        if cur.get("enabled") == ra.get("enabled") and cur.get("defaultAction") == ra.get("defaultAction"):
            continue
        body = dict(cur)
        body["enabled"] = ra.get("enabled", cur.get("enabled"))
        body["defaultAction"] = ra.get("defaultAction", cur.get("defaultAction"))
        body["priority"] = ra.get("priority", cur.get("priority"))
        s, _ = req("PUT", f"{base}/authentication/required-actions/{ra['alias']}", tok, body)
        print(f"  {ra['alias']} enabled={ra['enabled']}: HTTP {s}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--keycloak-url", required=True, help="e.g. https://test.sunbirded.org/auth")
    ap.add_argument("--admin-user", required=True)
    ap.add_argument("--admin-pass", required=True)
    ap.add_argument("--realm", default="sunbird")
    ap.add_argument("--new-realm-file", required=True)
    args = ap.parse_args()

    print(f"==> Authenticating to {args.keycloak_url}")
    kc_root = detect_kc_base(args.keycloak_url)
    tok = get_token(kc_root, args.admin_user, args.admin_pass)
    base = f"{kc_root}/admin/realms/{args.realm}"

    new = json.load(open(args.new_realm_file))

    print("\n==> Updating realm-level config...")
    patch_realm(base, tok, new)

    # Flows MUST be created before clients so authenticationFlowBindingOverrides
    # can be remapped to current Keycloak flow UUIDs.
    create_new_flows(base, tok, new)
    flow_remap = build_flow_uuid_remap(base, tok, new)
    print(f"  flow UUID remap entries: {len(flow_remap)}")

    update_clients(base, tok, new, flow_uuid_remap=flow_remap)
    update_required_actions(base, tok, new)

    print("\n==> Done. Users + sessions in DB untouched.")


if __name__ == "__main__":
    main()
