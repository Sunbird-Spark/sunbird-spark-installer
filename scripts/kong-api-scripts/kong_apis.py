try:
    # Python 3
    import urllib.request as urllib2
except ImportError:
    # Python 2
    import urllib2

import argparse, json, time

from common import get_apis, json_request, get_api_plugins, retrying_urlopen

def save_apis(kong_admin_api_url, input_apis):
    apis_url = "{}/services".format(kong_admin_api_url)
    saved_apis = get_apis(kong_admin_api_url)

    print("Number of input APIs : {}".format(len(input_apis)))
    print("Number of existing APIs : {}".format(len(saved_apis)))

    input_api_names = [api["name"] for api in input_apis]
    saved_api_names = [api["name"] for api in saved_apis]

    print("Input APIs : {}".format(input_api_names))
    print("Existing APIs : {}".format(saved_api_names))

    input_apis_to_be_created = [input_api for input_api in input_apis if input_api["name"] not in saved_api_names]
    input_apis_to_be_updated = [input_api for input_api in input_apis if input_api["name"] in saved_api_names]
    saved_api_to_be_deleted = [saved_api for saved_api in saved_apis if saved_api["name"] not in input_api_names]

    for input_api in input_apis_to_be_created:
        print("Adding API {}".format(input_api["name"]))
        service_response = json_request("POST", apis_url, _sanitized_api_data(input_api))
        service_data = json.loads(service_response.read())
        
        # Create route for the service if uris are specified
        if 'uris' in input_api:
            _create_route_for_service(kong_admin_api_url, service_data['id'], input_api)

    for input_api in input_apis_to_be_updated:
        print("Updating API {}".format(input_api["name"]))
        saved_api_id = [saved_api["id"] for saved_api in saved_apis if saved_api["name"] == input_api["name"]][0]
        input_api["id"] = saved_api_id
        json_request("PATCH", apis_url + "/" + saved_api_id, _sanitized_api_data(input_api))
        
        # Update routes if uris are specified
        if 'uris' in input_api:
            _update_routes_for_service(kong_admin_api_url, saved_api_id, input_api)

    for saved_api in saved_api_to_be_deleted:
        print("Deleting API {}".format(saved_api["name"]));
        json_request("DELETE", apis_url + "/" + saved_api["id"], "")

    for input_api in input_apis:
        _save_plugins_for_api(kong_admin_api_url, input_api)

def _create_route_for_service(kong_admin_api_url, service_id, input_api):
    """Create routes for a service in Kong 3.9.1"""
    routes_url = "{}/routes".format(kong_admin_api_url)
    
    route_data = {
        "service": {"id": service_id},
        "name": input_api["name"] + "-route-" + service_id[:8] + "-" + str(int(time.time()))[-4:]  # Make name truly unique with timestamp
    }
    
    # Add paths if uris are specified (Kong 3.9.1 uses 'paths' not 'uris')
    if 'uris' in input_api:
        uris = input_api["uris"]
        if isinstance(uris, list):
            route_data["paths"] = uris
        else:
            route_data["paths"] = [uris]
    
    # Note: strip_uri is not supported in Kong 3.9.1 Routes
    # Path stripping should be handled by upstream service or plugins
    
    print("Creating route for service {}: {}".format(service_id, route_data))
    json_request("POST", routes_url, route_data)

def _update_routes_for_service(kong_admin_api_url, service_id, input_api):
    """Update routes for a service in Kong 3.9.1"""
    routes_url = "{}/routes".format(kong_admin_api_url)
    
    # Get existing routes for this service
    existing_routes = json.loads(retrying_urlopen("{}?service.id={}".format(routes_url, service_id)).read())
    
    if isinstance(existing_routes, dict) and 'data' in existing_routes:
        existing_routes = existing_routes['data']
    elif not isinstance(existing_routes, list):
        existing_routes = []
    
    route_data = {
        "service": {"id": service_id},
        "name": input_api["name"] + "-route-" + service_id[:8] + "-" + str(int(time.time()))[-4:]  # Make name truly unique with timestamp
    }
    
    # Add paths if uris are specified (Kong 3.9.1 uses 'paths' not 'uris')
    if 'uris' in input_api:
        uris = input_api["uris"]
        if isinstance(uris, list):
            route_data["paths"] = uris
        else:
            route_data["paths"] = [uris]
    
    # Note: strip_uri is not supported in Kong 3.9.1 Routes
    
    if existing_routes:
        # Update existing route
        route_id = existing_routes[0]['id']
        print("Updating route {} for service {}: {}".format(route_id, service_id, route_data))
        json_request("PATCH", "{}/{}".format(routes_url, route_id), route_data)
    else:
        # Create new route
        print("Creating new route for service {}: {}".format(service_id, route_data))
        json_request("POST", routes_url, route_data)

def _save_plugins_for_api(kong_admin_api_url, input_api_details):
    get_plugins_max_page_size = 1000
    api_name = input_api_details["name"]
    input_plugins = input_api_details["plugins"]
    api_pugins_url = "{}/services/{}/plugins".format(kong_admin_api_url, api_name)
    saved_plugins_including_consumer_overrides = get_api_plugins(kong_admin_api_url, api_name)
    saved_plugins_without_consumer_overrides = [plugin for plugin in saved_plugins_including_consumer_overrides if not plugin.get('consumer_id')]

    saved_plugins = saved_plugins_without_consumer_overrides
    input_plugin_names = [input_plugin["name"] for input_plugin in input_plugins]
    saved_plugin_names = [saved_plugin["name"] for saved_plugin in saved_plugins]

    input_plugins_to_be_created = [input_plugin for input_plugin in input_plugins if input_plugin["name"] not in saved_plugin_names]
    input_plugins_to_be_updated = [input_plugin for input_plugin in input_plugins if input_plugin["name"] in saved_plugin_names]
    saved_plugins_to_be_deleted = [saved_plugin for saved_plugin in saved_plugins if saved_plugin["name"] not in input_plugin_names]

    for input_plugin in input_plugins_to_be_created:
        print("Adding plugin {} for API {}".format(input_plugin["name"], api_name));
        json_request("POST", api_pugins_url, input_plugin)

    for input_plugin in input_plugins_to_be_updated:
        print("Updating plugin {} for API {}".format(input_plugin["name"], api_name));
        saved_plugin_id = [saved_plugin["id"] for saved_plugin in saved_plugins if saved_plugin["name"] == input_plugin["name"]][0]
        input_plugin["id"] = saved_plugin_id
        
        # Special handling for JWT plugin - delete and recreate instead of update
        if input_plugin["name"] == "jwt":
            print("Deleting existing JWT plugin {} for API {} before recreating".format(saved_plugin_id, api_name));
            json_request("DELETE", api_pugins_url + "/" + saved_plugin_id, "")
            print("Creating new JWT plugin for API {}".format(api_name));
            json_request("POST", api_pugins_url, input_plugin)
        else:
            json_request("PATCH", api_pugins_url + "/" + saved_plugin_id, input_plugin)

    for saved_plugin in saved_plugins_to_be_deleted:
        print("Deleting plugin {} for API {}".format(saved_plugin["name"], api_name));
        json_request("DELETE", api_pugins_url + "/" + saved_plugin["id"], "")

def _sanitized_api_data(input_api):
    keys_to_ignore = ['plugins']
    sanitized_api_data = dict((key, input_api[key]) for key in input_api if key not in keys_to_ignore)
    
    # Kong 3.9.1 Service schema mapping
    # Old API fields -> New Service fields
    service_data = {}
    
    # Required field: host (from upstream_url or host) - NO PORT ALLOWED
    if 'upstream_url' in sanitized_api_data:
        # Extract host from upstream_url if it's a URL
        import re
        upstream_url = sanitized_api_data['upstream_url']
        if '://' in upstream_url:
            # Parse URL to get host and port separately
            match = re.match(r'https?://([^:/]+)(?::(\d+))?', upstream_url)
            if match:
                service_data['host'] = match.group(1)
                if match.group(2):  # Port was specified
                    service_data['port'] = int(match.group(2))
            else:
                # If no port in URL, use the whole thing as host
                service_data['host'] = upstream_url.replace('http://', '').replace('https://', '').split(':')[0]
        else:
            # Handle Kubernetes service names with ports
            if ':' in upstream_url:
                parts = upstream_url.split(':')
                service_data['host'] = parts[0]
                service_data['port'] = int(parts[1])
            else:
                service_data['host'] = upstream_url
    elif 'host' in sanitized_api_data:
        service_data['host'] = sanitized_api_data['host']
    
    # Map uris to routes (will be handled separately)
    # For now, create basic service
    if 'name' in sanitized_api_data:
        service_data['name'] = sanitized_api_data['name']
    
    # Add protocol if specified
    if 'protocol' in sanitized_api_data:
        service_data['protocol'] = sanitized_api_data['protocol']
    else:
        service_data['protocol'] = 'http'
    
    # Add port if specified (and not already set from upstream_url)
    if 'port' in sanitized_api_data and 'port' not in service_data:
        service_data['port'] = sanitized_api_data['port']
    
    # Add path if specified
    if 'path' in sanitized_api_data:
        service_data['path'] = sanitized_api_data['path']
    
    print("DEBUG: service_data = {}".format(service_data))
    return service_data

if  __name__ == "__main__":
    parser = argparse.ArgumentParser(description='Configure kong apis')
    parser.add_argument('apis_file_path', help='Path of the json file containing apis data')
    parser.add_argument('--kong-admin-api-url', help='Admin url for kong', default='http://localhost:8001')
    args = parser.parse_args()
    with open(args.apis_file_path) as apis_file:
        input_apis = json.load(apis_file)
        try:
            save_apis(args.kong_admin_api_url, input_apis)
        except urllib2.HTTPError as e:
            error_message = e.read()
            print(error_message)
            raise