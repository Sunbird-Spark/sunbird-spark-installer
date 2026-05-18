import urllib.request
import urllib.error
import argparse
import json
import copy

from common import get_apis, json_request, get_api_plugins, get_routes

def save_apis(kong_admin_api_url, input_apis, managed_by=None):
    """
    Kong 3.9.1 Upgrade: Save services and routes (replaces legacy /apis)
    """
    services_url = "{}/services".format(kong_admin_api_url)

    # ALL services in Kong — used to decide create vs update
    all_saved_services = get_apis(kong_admin_api_url)

    # Only OUR tagged services — used to decide safe deletes
    if managed_by:
        owned_saved_services = [s for s in all_saved_services if "managed-by:{}".format(managed_by) in (s.get("tags") or [])]
    else:
        owned_saved_services = all_saved_services   # no tag: own everything (full sync)

    input_apis = input_apis or []
    input_service_names   = [api["name"] for api in input_apis]
    all_saved_names       = [s["name"]   for s in all_saved_services]

    # CREATE: in our input, does not exist anywhere in Kong
    input_services_to_be_created = [api for api in input_apis if api["name"] not in all_saved_names]

    # UPDATE candidates: in our input, already exists in Kong
    potential_updates = [api for api in input_apis if api["name"] in all_saved_names]

    # DELETE: we own it (has our tag) but no longer in our input
    owned_services_to_be_deleted = [s for s in owned_saved_services if s["name"] not in input_service_names]

    stats = {
        "services": {"created": 0, "updated": 0, "deleted": 0, "skipped": 0},
        "routes": {"created": 0, "updated": 0, "deleted": 0, "skipped": 0},
        "plugins": {"created": 0, "updated": 0, "deleted": 0, "skipped": 0}
    }

    # Helper to check if service changed
    def _is_service_different(new_data, saved_service):
        for key in ["url", "retries", "connect_timeout", "write_timeout", "read_timeout"]:
            if key in new_data and new_data[key] != saved_service.get(key):
                return True
        # Check tags (adoption)
        new_tags = new_data.get("tags", [])
        saved_tags = saved_service.get("tags") or []
        if any(t not in saved_tags for t in new_tags):
            return True
        return False

    for input_service in input_services_to_be_created:
        print("Adding service {}".format(input_service["name"]))
        service_data = _convert_api_to_service(input_service, managed_by=managed_by)
        try:
            json_request("POST", services_url, service_data)
            stats["services"]["created"] += 1
        except Exception as e:
            print("  ✗ Error creating service {}: {}".format(input_service["name"], str(e)))

    for input_service in potential_updates:
        saved_service = [s for s in all_saved_services if s["name"] == input_service["name"]][0]
        service_data = _convert_api_to_service(input_service, managed_by=managed_by)
        
        if _is_service_different(service_data, saved_service):
            print("Updating service {}".format(input_service["name"]))
            try:
                json_request("PATCH", services_url + "/" + saved_service["id"], service_data)
                stats["services"]["updated"] += 1
            except Exception as e:
                print("  ✗ Error updating service {}: {}".format(input_service["name"], str(e)))
        else:
            stats["services"]["skipped"] += 1

    for saved_service in owned_services_to_be_deleted:
        service_id = saved_service["id"]
        service_name = saved_service["name"]
        print("Deleting owned orphan service {}".format(service_name))
        
        # Kong 3.x: Must delete routes BEFORE deleting the service
        try:
            assoc_routes = get_routes(kong_admin_api_url, service_name)
            for route in assoc_routes:
                print("  ✓ Deleting associated route {} before service removal".format(route["name"]))
                json_request("DELETE", "{}/{}/routes/{}".format(services_url, service_id, route["id"]), "")
                stats["routes"]["deleted"] += 1
        except Exception as e:
            print("  ⚠ Warning: Could not cleanup routes for service {}: {}".format(service_name, str(e)))

        try:
            json_request("DELETE", services_url + "/" + service_id, "")
            stats["services"]["deleted"] += 1
        except Exception as e:
            print("  ✗ Error deleting service {}: {}".format(service_name, str(e)))

    for input_api in input_apis:
        try:
            _save_routes_for_service(kong_admin_api_url, input_api, stats)
        except Exception as e:
            print("  ✗ Error processing routes for {}: {}".format(input_api["name"], str(e)))
            
        try:
            _save_plugins_for_service(kong_admin_api_url, input_api, stats)
        except Exception as e:
            print("  ✗ Error processing plugins for {}: {}".format(input_api["name"], str(e)))

    print("\n--- Kong API Onboarding Summary ---")
    print("Number of input services    : {}".format(len(input_apis or [])))
    print("Total services in Kong      : {}".format(len(all_saved_services or [])))
    print("Owned services in Kong      : {}".format(len(owned_saved_services or [])))
    print("Managed-by label            : {}".format(managed_by or "(none — full sync)"))
    print("----------------------------------\n")

def _convert_api_to_service(input_api, managed_by=None):
    """
    Convert Kong 0.14.1 API object to Kong 3.9.1 Service object.

    Kong 0.14.1 API properties → Kong 3.9.1 Service:
    - name → name (kept)
    - upstream_url → url (backend target)
    - retries → retries (kept)
    - connect_timeout → connect_timeout (kept)
    - write_timeout → write_timeout (kept)
    - read_timeout → read_timeout (kept)

    managed_by: When set, stamps a 'managed-by:<managed_by>' tag on the
                service so ownership-based sync knows which chart owns it.
    """
    service_data = {
        "name": input_api.get("name"),
    }

    # Map upstream_url to url (Kong 3.x terminology)
    if "upstream_url" in input_api:
        service_data["url"] = input_api["upstream_url"]
    elif "url" in input_api:
        service_data["url"] = input_api["url"]

    # Optional timeouts and retries
    if "retries" in input_api:
        service_data["retries"] = input_api["retries"]
    if "connect_timeout" in input_api:
        service_data["connect_timeout"] = input_api["connect_timeout"]
    if "write_timeout" in input_api:
        service_data["write_timeout"] = input_api["write_timeout"]
    if "read_timeout" in input_api:
        service_data["read_timeout"] = input_api["read_timeout"]

    # Stamp ownership tag so each chart only manages its own services
    if managed_by:
        service_data["tags"] = ["managed-by:{}".format(managed_by)]

    return service_data

def _save_routes_for_service(kong_admin_api_url, input_api_details, stats):
    """
    Kong 3.9.1: Save routes for the service.
    Routes define how requests are matched to the service.
    Handles: create, update, delete of routes
    """
    service_name = input_api_details["name"]
    routes_url = "{}/services/{}/routes".format(kong_admin_api_url, service_name)
    
    # Get existing routes for this service
    try:
        existing_routes = get_routes(kong_admin_api_url, service_name)
    except Exception as e:
        print("Warning: Could not fetch existing routes for {}: {}".format(service_name, str(e)))
        existing_routes = []
    
    # Extract route configuration from input API
    input_routes = input_api_details.get("routes", [])
    
    if not input_routes and "uris" in input_api_details:
        # Backward compatibility: convert legacy uris to routes
        uris = input_api_details.get("uris", [])
        if isinstance(uris, str):
            uris = [uris]
        input_routes = [{
            "paths": uris,
            "strip_path": input_api_details.get("strip_uri", True)
        }]
    
    # helper to check if route changed
    def _is_route_different(new, old):
        for key in ["paths", "strip_path", "preserve_host", "hosts", "methods", "protocols", "regex_priority"]:
            if key in new:
                new_val = new[key]
                old_val = old.get(key)
                # Sort lists for stable comparison (paths, hosts, methods, protocols)
                if isinstance(new_val, list) and isinstance(old_val, list):
                    if sorted(new_val) != sorted(old_val):
                        return True
                elif new_val != old_val:
                    return True
        return False

    input_route_names = []
    for idx, input_route in enumerate(input_routes):
        route_name = "{}-route-{}".format(service_name, idx)
        route_data = {
            "name": input_route.get("name", route_name),
            "paths": input_route.get("paths", input_route.get("uris", [])),
            "strip_path": input_route.get("strip_path", input_route.get("strip_uri", True)),
            "preserve_host": input_route.get("preserve_host", False)
        }
        
        if isinstance(route_data["paths"], str):
            route_data["paths"] = [route_data["paths"]]

        input_route_names.append(route_data["name"])
        
        # Optional route properties
        if "hosts" in input_route:
            route_data["hosts"] = input_route["hosts"]
        if "methods" in input_route:
            route_data["methods"] = input_route["methods"]
        if "protocols" in input_route:
            route_data["protocols"] = input_route["protocols"]
        if "regex_priority" in input_route:
            route_data["regex_priority"] = input_route["regex_priority"]
        
        # Check if route exists
        existing_route = next((r for r in existing_routes if r.get("name") == route_data["name"]), None)
        
        if existing_route:
            if _is_route_different(route_data, existing_route):
                print("  ✓ Updating route {} for service {}".format(route_data["name"], service_name))
                try:
                    json_request("PATCH", routes_url + "/" + existing_route["id"], route_data)
                    stats["routes"]["updated"] += 1
                except Exception as e:
                    print("  ✗ Error updating route: {}".format(str(e)))
            else:
                stats["routes"]["skipped"] += 1
        else:
            print("  ✓ Creating route {} for service {}".format(route_data["name"], service_name))
            try:
                json_request("POST", routes_url, route_data)
                stats["routes"]["created"] += 1
            except urllib.error.HTTPError as e:
                if e.code == 409:
                    # Route already exists, try to update it instead
                    print("  ℹ Route {} already exists, fetching to update".format(route_data["name"]))
                    try:
                        # Fetch all routes to find the existing one
                        all_routes_response = json.loads(urllib.request.urlopen(routes_url + "?size=100").read().decode('utf-8'))
                        existing_route = next((r for r in all_routes_response.get("data", []) if r.get("name") == route_data["name"]), None)
                        if existing_route:
                            print("  ✓ Updating existing route {} for service {}".format(route_data["name"], service_name))
                            json_request("PATCH", routes_url + "/" + existing_route["id"], route_data)
                            stats["routes"]["updated"] += 1
                        else:
                            print("  ✗ Route exists but could not find it: {}".format(route_data["name"]))
                    except Exception as update_err:
                        print("  ✗ Error updating existing route: {}".format(str(update_err)))
                else:
                    print("  ✗ Error creating route: HTTP {}".format(e.code))
            except Exception as e:
                print("  ✗ Error creating route: {}".format(str(e)))
    
    # Delete routes not in input
    routes_to_delete = [r for r in existing_routes if r.get("name") not in input_route_names]
    for route_to_delete in routes_to_delete:
        print("  ✓ Deleting route {} for service {}".format(route_to_delete["name"], service_name))
        try:
            json_request("DELETE", routes_url + "/" + route_to_delete["id"], "")
            stats["routes"]["deleted"] += 1
        except Exception as e:
            print("  ✗ Error deleting route: {}".format(str(e)))

def _save_plugins_for_service(kong_admin_api_url, input_api_details, stats):
    """
    Kong 3.9.1: Save plugins attached to the service (replaces /apis/{id}/plugins).
    Plugins are now attached to services in Kong 3.x.
    """
    service_name = input_api_details["name"]
    input_plugins = input_api_details.get("plugins", [])
    
    # Filter out None entries (shouldn't happen but safety check)
    input_plugins = [p for p in input_plugins if p is not None]
    
    plugins_url = "{}/services/{}/plugins".format(kong_admin_api_url, service_name)
    
    saved_plugins_including_consumer_overrides = get_api_plugins(kong_admin_api_url, service_name)
    saved_plugins_without_consumer_overrides = [plugin for plugin in saved_plugins_including_consumer_overrides if not plugin.get('consumer_id')]

    saved_plugins = saved_plugins_without_consumer_overrides
    input_plugin_names = [input_plugin["name"] for input_plugin in input_plugins]
    saved_plugin_names = [saved_plugin["name"] for saved_plugin in saved_plugins]

    # helper to check if plugin changed
    def _is_plugin_different(new, old):
        # We compare the config and enabled status
        new_config = new.get("config", {})
        old_config = old.get("config", {})
        
        # Simple recursive compare for dicts
        def dict_compare(d1, d2):
            if not isinstance(d1, dict) or not isinstance(d2, dict):
                # Handle lists
                if isinstance(d1, list) and isinstance(d2, list):
                    return sorted([str(v) for v in d1]) != sorted([str(v) for v in d2])
                return d1 != d2
            for k in set(d1.keys()).union(d2.keys()):
                if k not in d1 or k not in d2:
                    return True
                if dict_compare(d1[k], d2[k]):
                    return True
            return False

        if dict_compare(new_config, old_config):
            return True
        if new.get("enabled", True) != old.get("enabled", True):
            return True
        return False

    input_plugins_to_be_created = [input_plugin for input_plugin in input_plugins if input_plugin["name"] not in saved_plugin_names]
    input_plugins_to_be_updated = [input_plugin for input_plugin in input_plugins if input_plugin["name"] in saved_plugin_names]
    saved_plugins_to_be_deleted = [saved_plugin for saved_plugin in saved_plugins if saved_plugin["name"] not in input_plugin_names]
    
    # Delete plugins first
    for saved_plugin in saved_plugins_to_be_deleted:
        print("Deleting plugin {} for service {}".format(saved_plugin["name"], service_name));
        json_request("DELETE", plugins_url + "/" + saved_plugin["id"], "")
        stats["plugins"]["deleted"] += 1

    for input_plugin in input_plugins_to_be_created:
        print("Adding plugin {} for service {}".format(input_plugin["name"], service_name));
        input_plugin = _convert_plugin_for_kong_3(input_plugin)
        try:
            json_request("POST", plugins_url, input_plugin)
            stats["plugins"]["created"] += 1
        except Exception as e:
            print("ERROR: Failed to create plugin {} for service {}".format(input_plugin["name"], service_name))
            raise

    for input_plugin in input_plugins_to_be_updated:
        # Deep copy to ensure no shared state leaks between plugins
        # during transformation in _convert_plugin_for_kong_3
        converted_plugin = _convert_plugin_for_kong_3(copy.deepcopy(input_plugin))

        saved_plugin = [p for p in saved_plugins if p["name"] == input_plugin["name"]][0]

        if _is_plugin_different(converted_plugin, saved_plugin):
            print("Updating plugin {} for service {}".format(input_plugin["name"], service_name));
            converted_plugin["id"] = saved_plugin["id"]
            try:
                json_request("PATCH", plugins_url + "/" + saved_plugin["id"], converted_plugin)
                stats["plugins"]["updated"] += 1
            except Exception as e:
                print("  ✗ Error updating plugin {} for service {}: {}".format(input_plugin["name"], service_name, str(e)))
                print("    Request body: {}".format(json.dumps(converted_plugin)))
        else:
            stats["plugins"]["skipped"] += 1

def _convert_plugin_for_kong_3(plugin_input):
    """
    Convert plugin configuration for Kong 3.0+ compatibility.
    Includes strict schema cleaning to prevent contamination between plugins.
    """
    plugin = copy.deepcopy(plugin_input)
    plugin_name = plugin.get('name', '')
    
    if 'config' not in plugin or not plugin['config']:
        plugin['config'] = {}
    
    # Normalize dotted config keys from YAML (e.g., config.host → nested structure)
    dotted_keys_to_move = [k for k in plugin.keys() if k.startswith('config.')]
    for dotted_key in dotted_keys_to_move:
        path_parts = dotted_key.replace('config.', '', 1).split('.')
        value = plugin.pop(dotted_key)
        current = plugin['config']
        for part in path_parts[:-1]:
            if part not in current or not isinstance(current[part], dict):
                current[part] = {}
            current = current[part]
        current[path_parts[-1]] = value

    plugin_config = plugin.get('config', {})
    
    # Universal type conversion: Kong 3.9.1 requires proper types for numeric fields
    numeric_fields = ['port', 'timeout', 'size', 'hour', 'minute', 'second', 'day', 'month', 'year',
                      'error_code', 'status', 'limit', 'window_size', 'retry_count', 'max_retries',
                      'allowed_payload_size', 'max_body_size', 'max_request_size']
    for field in numeric_fields:
        if field in plugin_config and isinstance(plugin_config[field], (str, float)):
            try:
                plugin_config[field] = int(plugin_config[field])
            except (ValueError, TypeError):
                pass

    # Plugin-specific schema cleanup and transformations
    if plugin_name == 'acl':
        if 'whitelist' in plugin_config:
            plugin_config['allow'] = plugin_config.pop('whitelist')
        if 'blacklist' in plugin_config:
            plugin_config['deny'] = plugin_config.pop('blacklist')
        # ACL schema doesn't have allowed_payload_size, status, etc.
        valid_keys = ['allow', 'deny', 'hide_groups_header']
        plugin_config = {k: v for k, v in plugin_config.items() if k in valid_keys or k.startswith('_')}

    elif plugin_name == 'jwt':
        # Kong 3.x rejects these fields when null/legacy values are passed in.
        # Old Kong 0.14.1 ignored them silently — strip for schema compatibility.
        for k in ['algorithms', 'claims_to_verify', 'maximum_expiration']:
            plugin_config.pop(k, None)

        # Defensive: clear any stale anonymous-fallback config carried in from
        # earlier syncs. The new policy is strict JWT enforcement (no bypass);
        # routes that genuinely want anonymous access opt in via their ACL
        # allow list, not via the JWT plugin's anonymous fallback.
        # Must explicitly set to None (not pop) — Kong's plugin PATCH merges
        # fields, so omitting `anonymous` would leave any stale value intact.
        plugin_config['anonymous'] = None

        # Default key_claim_name = "kid" — covers the access tokens (t2)
        # that almost every protected route receives: RS256, kid in header,
        # opaque iss (from sunbird-apimanager-util TokenSignStep).
        #
        # The token-generation endpoints (e.g. refreshToken at
        # /auth/v1/refresh/token) receive an HS256 refresh token (t1) with
        # iss=<consumer_name> and no kid — those routes MUST opt out by
        # setting `config.key_claim_name: iss` explicitly in YAML.
        #
        # Set explicitly (not pop) so Kong's plugin PATCH overrides any
        # stale value left on existing plugins from earlier syncs.
        if 'key_claim_name' not in plugin_config:
            plugin_config['key_claim_name'] = 'kid'

    elif plugin_name == 'rate-limiting':
        if 'error_code' not in plugin_config:
            plugin_config['error_code'] = 429
        if 'error_message' not in plugin_config:
            plugin_config['error_message'] = 'API rate limit exceeded'
        # Strip fields that might have leaked from other plugins
        valid_keys = ['second', 'minute', 'hour', 'day', 'month', 'year', 'limit_by', 'policy', 
                      'fault_tolerant', 'redis_host', 'redis_port', 'redis_password', 'redis_timeout',
                      'redis_database', 'hide_client_headers', 'error_code', 'error_message']
        plugin_config = {k: v for k, v in plugin_config.items() if k in valid_keys or k.startswith('_')}

    elif plugin_name == 'request-size-limiting':
        # ONLY allow payload size fields
        valid_keys = ['allowed_payload_size', 'size_unit']
        plugin_config = {k: v for k, v in plugin_config.items() if k in valid_keys or k.startswith('_')}

    elif plugin_name == 'statsd':
        # STRIP contamination like allowed_payload_size which caused HTTP 400
        valid_keys = ['host', 'port', 'prefix', 'metrics', 'udp_packet_size', 'retry_count']
        plugin_config = {k: v for k, v in plugin_config.items() if k in valid_keys or k.startswith('_')}
    
    elif plugin_name == 'request-transformer':
        for action in ['add', 'append', 'remove', 'replace', 'rename']:
            if action in plugin_config and isinstance(plugin_config[action], dict):
                for field in ['headers', 'querystring', 'body']:
                    if field in plugin_config[action] and isinstance(plugin_config[action][field], str):
                        plugin_config[action][field] = [plugin_config[action][field]]

    plugin['config'] = plugin_config
    return plugin

def _sanitized_api_data(input_api):
    keys_to_ignore = ['plugins', 'routes']
    sanitized_api_data = dict((key, input_api[key]) for key in input_api if key not in keys_to_ignore)
    return sanitized_api_data

def _fetch_all_plugins(kong_admin_api_url):
    """
    Fetch every plugin from Kong's admin API, following pagination cursors.
    Kong caps `size` and returns a `next` link (relative or absolute) when
    more rows exist — a single page is not enough on deployments with more
    than a few hundred plugins.
    """
    plugins = []
    next_url = "{}/plugins?size=1000".format(kong_admin_api_url)
    while next_url:
        response = urllib.request.urlopen(next_url)
        payload = json.loads(response.read())
        plugins.extend(payload.get('data', []) or [])
        nxt = payload.get('next')
        if not nxt:
            break
        # Kong may return `next` as a path (e.g. "/plugins?offset=...") or a
        # full URL — normalise both to an absolute admin URL.
        if nxt.startswith('http://') or nxt.startswith('https://'):
            next_url = nxt
        else:
            next_url = "{}{}".format(kong_admin_api_url.rstrip('/'), nxt if nxt.startswith('/') else '/' + nxt)
    return plugins

def strip_legacy_anonymous_state(kong_admin_api_url):
    """
    Pre-sync cleanup: remove the lenient-anonymous bypass and the stale
    iss-based credential lookup that earlier versions of this script
    injected into Kong.

    Old behaviour (now reverted):
    - JWT plugins had config.anonymous = "portal_anonymous", so tokenless
      requests were silently treated as the portal_anonymous consumer.
    - ACL plugin allow lists had "portal_anonymous" appended, so the bypass
      consumer also passed ACL.
    - JWT plugins used config.key_claim_name = "iss" (Kong's default), which
      could not locate credentials registered by their `kid`.

    Kong's admin API uses PATCH merge semantics — fields not sent are left
    as-is — so those legacy values persist on every existing plugin until
    something explicitly overwrites them. This walks every JWT and ACL
    plugin and force-resets them so strict JWT enforcement actually applies
    after redeploy, regardless of whether save_apis later sees the plugin
    as "different".
    """
    print("\n=== Stripping legacy anonymous state from JWT + ACL plugins ===")

    try:
        all_plugins = _fetch_all_plugins(kong_admin_api_url)

        jwt_patched = 0
        for plugin in [p for p in all_plugins if p.get('name') == 'jwt']:
            cfg = plugin.get('config') or {}
            anon = cfg.get('anonymous')
            kcn = cfg.get('key_claim_name')

            patch_config = {}
            if anon:
                patch_config['anonymous'] = None
            # Force strict kid-based credential lookup. The old default
            # ("iss") could not find credentials registered under their
            # signing-key id, so requests fell back through the anonymous
            # bypass. Setting kid here closes that hole even if save_apis
            # later decides the plugin is otherwise unchanged.
            if kcn != 'kid':
                patch_config['key_claim_name'] = 'kid'

            if patch_config:
                patch_url = "{}/plugins/{}".format(kong_admin_api_url, plugin['id'])
                print("Resetting JWT plugin {}: {}".format(plugin['id'], patch_config))
                json_request("PATCH", patch_url, {'config': patch_config})
                jwt_patched += 1

        acl_cleaned = 0
        for plugin in [p for p in all_plugins if p.get('name') == 'acl']:
            allow_list = (plugin.get('config') or {}).get('allow') or []
            if 'portal_anonymous' in allow_list:
                new_allow = [g for g in allow_list if g != 'portal_anonymous']
                patch_url = "{}/plugins/{}".format(kong_admin_api_url, plugin['id'])
                print("Removing portal_anonymous from ACL plugin {}".format(plugin['id']))
                json_request("PATCH", patch_url, {'config': {'allow': new_allow}})
                acl_cleaned += 1

        print("Patched {} JWT plugins (cleared anonymous / set key_claim_name=kid), stripped portal_anonymous from {} ACL plugins".format(jwt_patched, acl_cleaned))
        print("=== Legacy anonymous state stripped ===\n")

    except Exception as e:
        print("ERROR stripping legacy anonymous state: {}".format(str(e)))
        # Best-effort — don't fail the whole sync over cleanup
        pass

if  __name__ == "__main__":
    parser = argparse.ArgumentParser(description='Configure kong services and routes (Kong 3.9.1)')
    parser.add_argument('apis_file_path', help='Path of the json file containing services data')
    parser.add_argument('--kong-admin-api-url', help='Admin url for kong', default='http://localhost:8001')
    parser.add_argument('--managed-by', default=None,
                        help='Ownership label for this chart (e.g. "core", "discussion-forum"). '
                             'Services are tagged managed-by:<label> on create/update. '
                             'Delete is scoped to only services with this tag, so charts '
                             'running concurrently never delete each other\'s APIs. '
                             'Omit for original full-sync behaviour (backward compat).')
    args = parser.parse_args()
    with open(args.apis_file_path) as apis_file:
        input_apis = json.load(apis_file)
        try:
            # Pre-sync cleanup: strip the legacy lenient-anonymous bypass
            # from any JWT/ACL plugins that still carry it from earlier sync
            # runs. Done BEFORE save_apis so YAML re-additions (e.g. routes
            # that explicitly list portal_anonymous in config.allow) stick.
            strip_legacy_anonymous_state(args.kong_admin_api_url)
            save_apis(args.kong_admin_api_url, input_apis, managed_by=args.managed_by)
        except urllib.error.HTTPError as e:
            error_message = e.read().decode('utf-8')
            print(error_message)
            raise
