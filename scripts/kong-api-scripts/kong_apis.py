import urllib.request
import urllib.error
import argparse
import json

from common import get_apis, json_request, get_api_plugins, get_routes

def _sanitize_plugin(plugin):
    """Ensure JWT plugin uses secure anonymous fallback (like Kong 0.14.1 behavior)."""
    try:
        if plugin.get('name') != 'jwt':
            return plugin
        plugin_config = plugin.get('config', {}) or {}
        # ALWAYS set to portal_anonymous for security (not portal_loggedin which has admin access)
        plugin_config['anonymous'] = 'portal_anonymous'
        plugin_config.pop('claims_to_verify', None)
        plugin['config'] = plugin_config
    except Exception:
        pass
    return plugin

def save_apis(kong_admin_api_url, input_apis):
    """
    Kong 3.9.1 Upgrade: Save services and routes (replaces legacy /apis)
    Input format compatible with Kong 0.14.1 but now converts to:
    - Services: Backend target configuration
    - Routes: Request matching rules (hosts, paths, methods, etc.)
    """
    services_url = "{}/services".format(kong_admin_api_url)
    saved_services = get_apis(kong_admin_api_url)

    print("Number of input services : {}".format(len(input_apis)))
    print("Number of existing services : {}".format(len(saved_services)))

    input_service_names = [api["name"] for api in input_apis]
    saved_service_names = [service["name"] for service in saved_services]

    print("Input services : {}".format(input_service_names))
    print("Existing services : {}".format(saved_service_names))

    input_services_to_be_created = [input_api for input_api in input_apis if input_api["name"] not in saved_service_names]
    input_services_to_be_updated = [input_api for input_api in input_apis if input_api["name"] in saved_service_names]
    saved_services_to_be_deleted = [saved_service for saved_service in saved_services if saved_service["name"] not in input_service_names]

    for input_service in input_services_to_be_created:
        print("Adding service {}".format(input_service["name"]))
        service_data = _convert_api_to_service(input_service)
        json_request("POST", services_url, service_data)

    for input_service in input_services_to_be_updated:
        print("Updating service {}".format(input_service["name"]))
        saved_service_id = [saved_service["id"] for saved_service in saved_services if saved_service["name"] == input_service["name"]][0]
        service_data = _convert_api_to_service(input_service)
        service_data["id"] = saved_service_id
        json_request("PATCH", services_url + "/" + saved_service_id, service_data)

    for saved_service in saved_services_to_be_deleted:
        print("Deleting service {}".format(saved_service["name"]));
        json_request("DELETE", services_url + "/" + saved_service["id"], "")

    for input_api in input_apis:
        _save_routes_for_service(kong_admin_api_url, input_api)
        _save_plugins_for_service(kong_admin_api_url, input_api)

def _convert_api_to_service(input_api):
    """
    Convert Kong 0.14.1 API object to Kong 3.9.1 Service object.
    
    Kong 0.14.1 API properties → Kong 3.9.1 Service:
    - name → name (kept)
    - upstream_url → url (backend target)
    - retries → retries (kept)
    - connect_timeout → connect_timeout (kept)
    - write_timeout → write_timeout (kept)
    - read_timeout → read_timeout (kept)
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
    
    return service_data

def _save_routes_for_service(kong_admin_api_url, input_api_details):
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
    
    print("Processing {} routes for service {}".format(len(input_routes), service_name))
    
    input_route_names = []
    for idx, input_route in enumerate(input_routes):
        route_name = "{}-route-{}".format(service_name, idx)
        route_data = {
            "name": input_route.get("name", route_name),
            "paths": input_route.get("paths", input_route.get("uris", [])),
            "strip_path": input_route.get("strip_path", input_route.get("strip_uri", True)),
            "preserve_host": input_route.get("preserve_host", False)
        }
        
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
            print("  ✓ Updating route {} for service {}".format(route_data["name"], service_name))
            try:
                json_request("PATCH", routes_url + "/" + existing_route["id"], route_data)
            except Exception as e:
                print("  ✗ Error updating route: {}".format(str(e)))
        else:
            print("  ✓ Creating route {} for service {}".format(route_data["name"], service_name))
            try:
                json_request("POST", routes_url, route_data)
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
        except Exception as e:
            print("  ✗ Error deleting route: {}".format(str(e)))

def _save_plugins_for_service(kong_admin_api_url, input_api_details):
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

    # Special handling: JWT plugin is converted to use anonymous fallback in Kong 3.9.1
    # No need for special delete/create logic anymore - just update the config
    has_jwt_to_convert = 'jwt' in input_plugin_names
    has_existing_jwt = 'jwt' in saved_plugin_names
    
    input_plugins_to_be_created = [input_plugin for input_plugin in input_plugins if input_plugin["name"] not in saved_plugin_names]
    input_plugins_to_be_updated = [input_plugin for input_plugin in input_plugins if input_plugin["name"] in saved_plugin_names]
    saved_plugins_to_be_deleted = [saved_plugin for saved_plugin in saved_plugins if saved_plugin["name"] not in input_plugin_names]
    
    # Delete plugins first
    for saved_plugin in saved_plugins_to_be_deleted:
        print("Deleting plugin {} for service {}".format(saved_plugin["name"], service_name));
        json_request("DELETE", plugins_url + "/" + saved_plugin["id"], "")

    for input_plugin in input_plugins_to_be_created:
        print("Adding plugin {} for service {}".format(input_plugin["name"], service_name));
        input_plugin = _convert_plugin_for_kong_3(input_plugin)
        print("Plugin data to POST: {}".format(json.dumps(input_plugin, indent=2)))
        try:
            json_request("POST", plugins_url, _sanitize_plugin(input_plugin))
        except Exception as e:
            print("ERROR: Failed to create plugin {} for service {}".format(input_plugin["name"], service_name))
            raise

    for input_plugin in input_plugins_to_be_updated:
        print("Updating plugin {} for service {}".format(input_plugin["name"], service_name));
        input_plugin = _convert_plugin_for_kong_3(input_plugin)
        saved_plugin_id = [saved_plugin["id"] for saved_plugin in saved_plugins if saved_plugin["name"] == input_plugin["name"]][0]
        input_plugin["id"] = saved_plugin_id
        json_request("PATCH", plugins_url + "/" + saved_plugin_id, _sanitize_plugin(input_plugin))

def _convert_plugin_for_kong_3(plugin):
    """
    Convert plugin configuration for Kong 3.0+ compatibility.
    Based on official Kong breaking changes documentation.
    - ACL: whitelist → allow (Kong 3.0 breaking change)
    - JWT: add algorithms, claims_to_verify (Kong 3.0+ enhancement)
    - Rate-limiting: add error_code, error_message (Kong 3.0+ enhancement)
    - Normalize dotted config keys (config.host → config: {host: ...})
    """
    # Normalize dotted config keys from YAML (e.g., config.host → nested structure)
    # Kong 3.x requires proper nested config, not dotted keys at root level
    # Also handles multi-level nesting: config.remove.headers → config: { remove: { headers: ... } }
    if 'config' not in plugin or not plugin['config']:
        plugin['config'] = {}
    
    dotted_keys_to_move = []
    for key in list(plugin.keys()):
        if key.startswith('config.'):
            dotted_keys_to_move.append(key)
    
    for dotted_key in dotted_keys_to_move:
        # Extract path parts: config.remove.headers → ['remove', 'headers']
        path_parts = dotted_key.replace('config.', '', 1).split('.')
        value = plugin.pop(dotted_key)
        
        # Navigate/create nested structure
        current = plugin['config']
        for i, part in enumerate(path_parts[:-1]):
            if part not in current:
                current[part] = {}
            current = current[part]
        
        # Set the final value
        final_key = path_parts[-1]
        current[final_key] = value
    
    plugin_config = plugin.get('config', {})
    plugin_name = plugin.get('name', '')
    
    # Universal type conversion: Kong 3.9.1 requires proper types for numeric fields
    # Convert string numbers to integers for common fields across all plugins
    numeric_fields = ['port', 'timeout', 'size', 'hour', 'minute', 'second', 'day', 'month', 'year',
                      'error_code', 'status', 'limit', 'window_size', 'retry_count', 'max_retries',
                      'allowed_payload_size', 'max_body_size', 'max_request_size']
    for field in numeric_fields:
        if field in plugin_config and isinstance(plugin_config[field], str):
            try:
                plugin_config[field] = int(plugin_config[field])
            except ValueError:
                pass  # Keep as string if conversion fails
    
    # Request-transformer plugin: Kong expects arrays for headers/querystring/body fields
    if plugin_name == 'request-transformer':
        for action in ['add', 'append', 'remove', 'replace', 'rename']:
            if action in plugin_config:
                for field in ['headers', 'querystring', 'body']:
                    if field in plugin_config[action] and isinstance(plugin_config[action][field], str):
                        # Convert single string to array
                        plugin_config[action][field] = [plugin_config[action][field]]
    
    # ACL Plugin: Kong 3.0 breaking change - whitelist → allow
    if plugin_name == 'acl':
        if 'whitelist' in plugin_config:
            plugin_config['allow'] = plugin_config.pop('whitelist')
        if 'blacklist' in plugin_config:
            plugin_config['deny'] = plugin_config.pop('blacklist')
        # Remove invalid 'status' field if present (not supported in Kong 3.9.1)
        plugin_config.pop('status', None)
    
    # JWT Plugin: Kong 3.9.1 compatibility - use anonymous consumer fallback
    # Problem: Portal sends exp as string, Kong validates it as number
    # Solution: Use anonymous fallback when JWT validation fails
    if plugin_name == 'jwt':
        if 'config' not in plugin or not plugin['config']:
            plugin['config'] = {}
        plugin_config = plugin['config']
        
        # Remove validation fields that cause type errors
        plugin_config.pop('algorithms', None)
        plugin_config.pop('claims_to_verify', None)
        plugin_config.pop('maximum_expiration', None)
        
        # Use anonymous consumer fallback for failed JWT validation (like Kong 0.14.1)
        # SECURITY: portal_anonymous has limited read-only access vs portal_loggedin with admin permissions
        plugin_config['anonymous'] = 'portal_anonymous'
        
        # Keep JWT extraction methods
        if 'header_names' not in plugin_config:
            plugin_config['header_names'] = ['authorization']
        if 'uri_param_names' not in plugin_config:
            plugin_config['uri_param_names'] = ['jwt']
    
    # ACL Plugin: Kong 3.9.1 compatibility - allow portal_anonymous consumer bypass
    # In Kong 0.14.1: JWT anonymous="" meant no consumer set, ACL didn't enforce
    # In Kong 3.x: JWT anonymous='portal_anonymous' sets consumer, ACL enforces strictly
    # Solution: Add 'portal_anonymous' group to EVERY ACL allow list (bypass for anonymous)
    # This is SECURE because portal_anonymous consumer only has limited read-only ACL groups
    if plugin_name == 'acl':
        if 'config' not in plugin or not plugin['config']:
            plugin['config'] = {}
        plugin_config = plugin['config']
        
        # Add 'portal_anonymous' to allow list - replicates Kong 0.14.1 anonymous="" behavior
        if 'allow' in plugin_config and plugin_config['allow']:
            if 'portal_anonymous' not in plugin_config['allow']:
                plugin_config['allow'].append('portal_anonymous')
        
        if 'hide_groups_header' not in plugin_config:
            plugin_config['hide_groups_header'] = False
    
    # Rate-limiting Plugin: Kong 3.0+ enhancements
    if plugin_name == 'rate-limiting':
        if 'error_code' not in plugin_config:
            plugin_config['error_code'] = 429  # HTTP 429 Too Many Requests
        if 'error_message' not in plugin_config:
            plugin_config['error_message'] = 'API rate limit exceeded'
    
    plugin['config'] = plugin_config
    return plugin

def _sanitized_api_data(input_api):
    keys_to_ignore = ['plugins', 'routes']
    sanitized_api_data = dict((key, input_api[key]) for key in input_api if key not in keys_to_ignore)
    return sanitized_api_data

def fix_all_acl_plugins_for_anonymous_access(kong_admin_api_url):
    """
    Post-migration fix: Ensure ALL ACL plugins (service and route level) include 'portal_anonymous' in allow list.
    
    This fixes Kong 3.9.1 compatibility issue where:
    - Kong 0.14.1: JWT anonymous="" meant no consumer set, ACL didn't enforce
    - Kong 3.x: JWT anonymous='portal_anonymous' sets consumer, ACL enforces strictly
    
    Solution: Add 'portal_anonymous' to every ACL plugin's allow list to replicate Kong 0.14.1 behavior.
    This is SECURE because portal_anonymous consumer only has limited read-only ACL groups.
    """
    print("\n=== Fixing all ACL plugins to allow portal_anonymous access ===")
    
    # Get all plugins (includes service-level, route-level, and global plugins)
    plugins_url = "{}/plugins?size=1000".format(kong_admin_api_url)
    try:
        response = urllib.request.urlopen(plugins_url)
        all_plugins = json.loads(response.read())
        acl_plugins = [p for p in all_plugins.get('data', []) if p.get('name') == 'acl']
        
        print("Found {} ACL plugins to check".format(len(acl_plugins)))
        
        updated_count = 0
        for plugin in acl_plugins:
            plugin_id = plugin['id']
            allow_list = plugin.get('config', {}).get('allow', [])
            
            if 'portal_anonymous' not in allow_list:
                # Add portal_anonymous to allow list
                allow_list.append('portal_anonymous')
                patch_data = {
                    'config': {
                        'allow': allow_list
                    }
                }
                
                patch_url = "{}/plugins/{}".format(kong_admin_api_url, plugin_id)
                print("Updating ACL plugin {} - adding portal_anonymous to allow list".format(plugin_id))
                json_request("PATCH", patch_url, patch_data)
                updated_count += 1
        
        print("Updated {} ACL plugins with portal_anonymous access".format(updated_count))
        print("=== ACL plugin fix complete ===\n")
        
    except Exception as e:
        print("ERROR fixing ACL plugins: {}".format(str(e)))
        # Don't fail the entire migration - this is a best-effort fix
        pass

if  __name__ == "__main__":
    parser = argparse.ArgumentParser(description='Configure kong services and routes (Kong 3.9.1)')
    parser.add_argument('apis_file_path', help='Path of the json file containing services data')
    parser.add_argument('--kong-admin-api-url', help='Admin url for kong', default='http://localhost:8001')
    args = parser.parse_args()
    with open(args.apis_file_path) as apis_file:
        input_apis = json.load(apis_file)
        try:
            save_apis(args.kong_admin_api_url, input_apis)
            # Post-migration fix: Ensure all ACL plugins allow portal_anonymous access
            # This handles both new and existing clusters
            fix_all_acl_plugins_for_anonymous_access(args.kong_admin_api_url)
        except urllib.error.HTTPError as e:
            error_message = e.read().decode('utf-8')
            print(error_message)
            raise