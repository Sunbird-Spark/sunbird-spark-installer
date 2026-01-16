# import argparse
# import json
# import requests
# from common import get_apis, json_request, get_api_plugins

# try:
#     string_types = basestring  # Python 2
# except NameError:
#     string_types = str  # Python 3

# def save_apis(kong_admin_api_url, input_apis):
#     services_url = "{}/services".format(kong_admin_api_url)
#     saved_services = get_apis(kong_admin_api_url)

#     print("Number of input APIs : {}".format(len(input_apis)))
#     print("Number of existing services : {}".format(len(saved_services)))

#     input_api_names = [api["name"] for api in input_apis]
#     saved_api_names = [api["name"] for api in saved_services]

#     input_apis_to_be_created = [api for api in input_apis if api["name"] not in saved_api_names]
#     input_apis_to_be_updated = [api for api in input_apis if api["name"] in saved_api_names]
#     saved_apis_to_be_deleted = [api for api in saved_services if api["name"] not in input_api_names]

#     for api in input_apis_to_be_created:
#         print("Adding service {}".format(api['name']))
#         service_data = _create_service_data(api)
#         json_request("POST", services_url, service_data)
#         if 'uris' in api:
#             _create_route_for_service(kong_admin_api_url, api["name"], api)

#     for api in input_apis_to_be_updated:
#         print("Updating service {}".format(api['name']))
#         saved_api_id = [s["id"] for s in saved_services if s["name"] == api["name"]][0]
#         service_data = _create_service_data(api)
#         api["id"] = saved_api_id
#         json_request("PATCH", "{}/{}".format(services_url, saved_api_id), service_data)
#         if 'uris' in api:
#             _update_route_for_service(kong_admin_api_url, saved_api_id, api)

#     # Optional: Uncomment to delete services not in input
#     # for api in saved_apis_to_be_deleted:
#     #     print("Deleting service {}".format(api['name']))
#     #     try:
#     #         json_request("DELETE", "{}/{}".format(services_url, api['id']), "")
#     #     except Exception as e:
#     #         print("Warning: Could not delete service {}: {}".format(api['name'], e))

#     # Skip plugin management for speed - focus on creating/updating services and routes first
#     # Uncomment below to enable plugin management
#     # for api in input_apis:
#     #     _save_plugins_for_service(kong_admin_api_url, api)
    
#     print("\n" + "="*80)
#     print("SUMMARY: Kong APIs Configuration Complete")
#     print("="*80)
#     print("Total input APIs: {}".format(len(input_apis)))
#     print("Total services created: {}".format(len(input_apis_to_be_created)))
#     print("Total services updated: {}".format(len(input_apis_to_be_updated)))
#     print("Total services skipped (not deleted): {}".format(len(saved_apis_to_be_deleted)))
#     print("="*80 + "\n")

# def _create_service_data(api):
#     service_data = {
#         "name": api["name"],
#         "url": api["upstream_url"]
#     }
#     upstream_url = api["upstream_url"]
#     if '://' in upstream_url:
#         protocol = upstream_url.split('://')[0]
#         host_port_path = upstream_url.split('://')[1]
#     else:
#         protocol = 'http'
#         host_port_path = upstream_url
#     if ':' in host_port_path:
#         parts = host_port_path.split(':', 1)
#         host = parts[0]
#         port_path = parts[1]
#         if '/' in port_path:
#             port, path = port_path.split('/', 1)
#             service_data['host'] = host
#             service_data['port'] = int(port)
#             service_data['protocol'] = protocol
#             service_data['path'] = '/' + path
#         else:
#             service_data['host'] = host
#             service_data['port'] = int(port_path)
#             service_data['protocol'] = protocol
#     else:
#         service_data['host'] = host_port_path
#         service_data['port'] = 80 if protocol == 'http' else 443
#         service_data['protocol'] = protocol
#     return service_data

# def _create_route_for_service(kong_admin_api_url, service_name, api):
#     routes_url = "{}/routes".format(kong_admin_api_url)
#     services_url = "{}/services".format(kong_admin_api_url)
#     try:
#         services_response = json_request("GET", "{}?name={}".format(services_url, service_name), {})
#         services_data = json.loads(services_response.read())
#         services = services_data['data'] if isinstance(services_data, dict) and 'data' in services_data else services_data
#         if not services:
#             print("Warning: Could not find service {} for route creation".format(service_name))
#             return
#         service_id = services[0]['id']
#     except Exception as e:
#         print("Warning: Could not get service ID for route creation: {}".format(e))
#         return
#     target_paths = api.get('uris', [])
#     if isinstance(target_paths, string_types):
#         target_paths = [target_paths]
#     elif not isinstance(target_paths, list):
#         target_paths = [target_paths] if target_paths else []
#     target_paths = [path if isinstance(path, string_types) else str(path) for path in target_paths]
#     route_data = {
#         "service": {"id": service_id},
#         "name": api["name"] + "-route",
#         "paths": target_paths
#     }
#     print("Creating route for service {}: {}".format(service_id, route_data))
#     json_request("POST", routes_url, route_data)

# def _update_route_for_service(kong_admin_api_url, service_id, api):
#     routes_url = "{}/routes".format(kong_admin_api_url)
#     try:
#         existing_routes_response = json_request("GET", "{}?service.id={}".format(routes_url, service_id), {})
#         existing_routes_data = json.loads(existing_routes_response.read())
#         existing_routes = existing_routes_data['data'] if isinstance(existing_routes_data, dict) and 'data' in existing_routes_data else existing_routes_data
#     except Exception:
#         existing_routes = []
#     target_paths = api.get('uris', [])
#     if isinstance(target_paths, string_types):
#         target_paths = [target_paths]
#     elif not isinstance(target_paths, list):
#         target_paths = [target_paths] if target_paths else []
#     target_paths = [path if isinstance(path, string_types) else str(path) for path in target_paths]
#     route_data = {
#         "service": {"id": service_id},
#         "name": api["name"] + "-route",
#         "paths": target_paths
#     }
#     if existing_routes:
#         existing_route = existing_routes[0]
#         print("Updating route {} for service {}: {}".format(existing_route['id'], service_id, route_data))
#         json_request("PATCH", "{}/{}".format(routes_url, existing_route['id']), route_data)
#     else:
#         print("Creating new route for service {}: {}".format(service_id, route_data))
#         json_request("POST", routes_url, route_data)

# def _save_plugins_for_service(kong_admin_api_url, api):
#     api_name = api["name"]
#     input_plugins = api.get("plugins", [])
#     if not input_plugins:
#         return
#     # Get service ID
#     services_url = "{}/services".format(kong_admin_api_url)
#     try:
#         services_response = json_request("GET", "{}?name={}".format(services_url, api_name), {})
#         services_data = json.loads(services_response.read())
#         services = services_data['data'] if isinstance(services_data, dict) and 'data' in services_data else services_data
#         if not services:
#             print("Warning: Could not find service {} for plugin management".format(api_name))
#             return
#         service_id = services[0]['id']
#     except Exception as e:
#         print("Warning: Could not get service ID for plugin management: {}".format(e))
#         return
#     plugins_url = "{}/services/{}/plugins".format(kong_admin_api_url, service_id)
#     try:
#         plugins_response = json_request("GET", plugins_url, {})
#         plugins_data = json.loads(plugins_response.read())
#         saved_plugins = plugins_data['data'] if isinstance(plugins_data, dict) and 'data' in plugins_data else plugins_data
#     except Exception as e:
#         print("Warning: Could not get plugins for service {}: {}".format(api_name, e))
#         saved_plugins = []
#     input_plugin_names = [p["name"] for p in input_plugins]
#     saved_plugin_names = [p["name"] for p in saved_plugins]
#     input_plugins_to_be_created = [p for p in input_plugins if p["name"] not in saved_plugin_names]
#     input_plugins_to_be_updated = [p for p in input_plugins if p["name"] in saved_plugin_names]
#     saved_plugins_to_be_deleted = [p for p in saved_plugins if p["name"] not in input_plugin_names]
#     for p in input_plugins_to_be_created:
#         print("Adding plugin {} for service {}".format(p['name'], api_name))
#         try:
#             json_request("POST", plugins_url, p)
#         except Exception as e:
#             print("Warning: Failed to add plugin {}: {}".format(p['name'], e))
#     for p in input_plugins_to_be_updated:
#         print("Updating plugin {} for service {}".format(p['name'], api_name))
#         try:
#             saved_plugin_id = [sp["id"] for sp in saved_plugins if sp["name"] == p["name"]][0]
#             p["id"] = saved_plugin_id
#             json_request("PATCH", "{}/{}".format(plugins_url, saved_plugin_id), p)
#         except Exception as e:
#             print("Warning: Failed to update plugin {}: {}".format(p['name'], e))
#     for sp in saved_plugins_to_be_deleted:
#         print("Deleting plugin {} for service {}".format(sp['name'], api_name))
#         try:
#             json_request("DELETE", "{}/{}".format(plugins_url, sp['id']), "")
#         except Exception as e:
#             print("Warning: Failed to delete plugin {}: {}".format(sp['name'], e))

# def _sanitized_api_data(api):
#     keys_to_ignore = ['plugins']
#     return {k: api[k] for k in api if k not in keys_to_ignore}

# if __name__ == "__main__":
#     parser = argparse.ArgumentParser(description='Configure kong apis')
#     parser.add_argument('apis_file_path', help='Path of the json file containing apis data')
#     parser.add_argument('--kong-admin-api-url', help='Admin url for kong', default='http://localhost:8001')
#     args = parser.parse_args()
#     with open(args.apis_file_path) as apis_file:
#         input_apis = json.load(apis_file)
#         try:
#             save_apis(args.kong_admin_api_url, input_apis)
#         except requests.HTTPError as e:
#             print(e.response.text)
#             raise
import argparse
import json
import requests
from common import get_apis, json_request, get_api_plugins

try:
    string_types = basestring  # Python 2
except NameError:
    string_types = str  # Python 3

def save_apis(kong_admin_api_url, input_apis):
    services_url = "{}/services".format(kong_admin_api_url)
    saved_services = get_apis(kong_admin_api_url)

    print("Number of input APIs : {}".format(len(input_apis)))
    print("Number of existing services : {}".format(len(saved_services)))

    input_api_names = [api["name"] for api in input_apis]
    saved_api_names = [api["name"] for api in saved_services]

    input_apis_to_be_created = [api for api in input_apis if api["name"] not in saved_api_names]
    input_apis_to_be_updated = [api for api in input_apis if api["name"] in saved_api_names]
    saved_apis_to_be_deleted = [api for api in saved_services if api["name"] not in input_api_names]

    for api in input_apis_to_be_created:
        print("Adding service {}".format(api['name']))
        service_data = _create_service_data(api)
        json_request("POST", services_url, service_data)
        if 'uris' in api:
            _create_route_for_service(kong_admin_api_url, api["name"], api)

    for api in input_apis_to_be_updated:
        print("Updating service {}".format(api['name']))
        saved_api_id = [s["id"] for s in saved_services if s["name"] == api["name"]][0]
        service_data = _create_service_data(api)
        api["id"] = saved_api_id
        try:
            json_request("PATCH", "{}/{}".format(services_url, saved_api_id), service_data)
        except Exception as e:
            print("ERROR updating service {}: {}".format(api['name'], str(e)))
            import traceback
            traceback.print_exc()
            raise
        if 'uris' in api:
            try:
                _update_route_for_service(kong_admin_api_url, saved_api_id, api)
            except Exception as e:
                print("ERROR updating route for service {}: {}".format(api['name'], str(e)))
                import traceback
                traceback.print_exc()
                raise

    # Optional: Uncomment to delete services not in input
    # for api in saved_apis_to_be_deleted:
    #     print("Deleting service {}".format(api['name']))
    #     try:
    #         json_request("DELETE", "{}/{}".format(services_url, api['id']), "")
    #     except Exception as e:
    #         print("Warning: Could not delete service {}: {}".format(api['name'], e))

    # Skip plugin management for speed - focus on creating/updating services and routes first
    # Uncomment below to enable plugin management
    # for api in input_apis:
    #     _save_plugins_for_service(kong_admin_api_url, api)
    
    print("\n" + "="*80)
    print("SUMMARY: Kong APIs Configuration Complete")
    print("="*80)
    print("Total input APIs: {}".format(len(input_apis)))
    print("Total services created: {}".format(len(input_apis_to_be_created)))
    print("Total services updated: {}".format(len(input_apis_to_be_updated)))
    print("Total services skipped (not deleted): {}".format(len(saved_apis_to_be_deleted)))
    print("="*80 + "\n")

def _create_service_data(api):
    service_data = {
        "name": api["name"],
        "url": api["upstream_url"]
    }
    upstream_url = api["upstream_url"]
    if '://' in upstream_url:
        protocol = upstream_url.split('://')[0]
        host_port_path = upstream_url.split('://')[1]
    else:
        protocol = 'http'
        host_port_path = upstream_url
    if ':' in host_port_path:
        parts = host_port_path.split(':', 1)
        host = parts[0]
        port_path = parts[1]
        if '/' in port_path:
            port, path = port_path.split('/', 1)
            service_data['host'] = host
            service_data['port'] = int(port)
            service_data['protocol'] = protocol
            service_data['path'] = '/' + path
        else:
            service_data['host'] = host
            service_data['port'] = int(port_path)
            service_data['protocol'] = protocol
    else:
        service_data['host'] = host_port_path
        service_data['port'] = 80 if protocol == 'http' else 443
        service_data['protocol'] = protocol
    return service_data

def _create_route_for_service(kong_admin_api_url, service_name, api):
    routes_url = "{}/routes".format(kong_admin_api_url)
    services_url = "{}/services".format(kong_admin_api_url)
    try:
        services_response = json_request("GET", "{}?name={}".format(services_url, service_name), {})
        services_data = json.loads(services_response.read())
        services = services_data['data'] if isinstance(services_data, dict) and 'data' in services_data else services_data
        if not services:
            print("Warning: Could not find service {} for route creation".format(service_name))
            return
        service_id = services[0]['id']
    except Exception as e:
        print("Warning: Could not get service ID for route creation: {}".format(e))
        return
    target_paths = api.get('uris', [])
    if isinstance(target_paths, string_types):
        target_paths = [target_paths]
    elif not isinstance(target_paths, list):
        target_paths = [target_paths] if target_paths else []
    target_paths = [path if isinstance(path, string_types) else str(path) for path in target_paths]
    route_data = {
        "service": {"id": service_id},
        "name": api["name"] + "-route",
        "paths": target_paths
    }
    print("Creating route for service {}: {}".format(service_id, route_data))
    json_request("POST", routes_url, route_data)

def _update_route_for_service(kong_admin_api_url, service_id, api):
    routes_url = "{}/routes".format(kong_admin_api_url)
    try:
        existing_routes_response = json_request("GET", "{}?service.id={}".format(routes_url, service_id), {})
        existing_routes_data = json.loads(existing_routes_response.read())
        existing_routes = existing_routes_data['data'] if isinstance(existing_routes_data, dict) and 'data' in existing_routes_data else existing_routes_data
    except Exception:
        existing_routes = []
    target_paths = api.get('uris', [])
    if isinstance(target_paths, string_types):
        target_paths = [target_paths]
    elif not isinstance(target_paths, list):
        target_paths = [target_paths] if target_paths else []
    target_paths = [path if isinstance(path, string_types) else str(path) for path in target_paths]
    route_data = {
        "service": {"id": service_id},
        "name": api["name"] + "-route",
        "paths": target_paths
    }
    if existing_routes:
        existing_route = existing_routes[0]
        print("Updating route {} for service {}: {}".format(existing_route['id'], service_id, route_data))
        json_request("PATCH", "{}/{}".format(routes_url, existing_route['id']), route_data)
    else:
        print("Creating new route for service {}: {}".format(service_id, route_data))
        json_request("POST", routes_url, route_data)

def _save_plugins_for_service(kong_admin_api_url, api):
    api_name = api["name"]
    input_plugins = api.get("plugins", [])
    if not input_plugins:
        return
    # Filter out None values from plugins list (can happen with template variables)
    input_plugins = [p for p in input_plugins if p is not None]
    if not input_plugins:
        return
    # Get service ID
    services_url = "{}/services".format(kong_admin_api_url)
    try:
        services_response = json_request("GET", "{}?name={}".format(services_url, api_name), {})
        services_data = json.loads(services_response.read())
        services = services_data['data'] if isinstance(services_data, dict) and 'data' in services_data else services_data
        if not services:
            print("Warning: Could not find service {} for plugin management".format(api_name))
            return
        service_id = services[0]['id']
    except Exception as e:
        print("Warning: Could not get service ID for plugin management: {}".format(e))
        return
    plugins_url = "{}/services/{}/plugins".format(kong_admin_api_url, service_id)
    try:
        plugins_response = json_request("GET", plugins_url, {})
        plugins_data = json.loads(plugins_response.read())
        saved_plugins = plugins_data['data'] if isinstance(plugins_data, dict) and 'data' in plugins_data else plugins_data
    except Exception as e:
        print("Warning: Could not get plugins for service {}: {}".format(api_name, e))
        saved_plugins = []
    input_plugin_names = [p["name"] for p in input_plugins]
    saved_plugin_names = [p["name"] for p in saved_plugins]
    input_plugins_to_be_created = [p for p in input_plugins if p["name"] not in saved_plugin_names]
    input_plugins_to_be_updated = [p for p in input_plugins if p["name"] in saved_plugin_names]
    saved_plugins_to_be_deleted = [p for p in saved_plugins if p["name"] not in input_plugin_names]
    for p in input_plugins_to_be_created:
        print("Adding plugin {} for service {}".format(p['name'], api_name))
        try:
            json_request("POST", plugins_url, p)
        except Exception as e:
            error_msg = str(e)
            if hasattr(e, 'read'):
                try:
                    error_msg = e.read()
                except:
                    pass
            print("ERROR: Failed to add plugin {} for service {}: {}".format(p['name'], api_name, error_msg))
            print("ERROR: Plugin config was: {}".format(json.dumps(p, indent=2)))
    for p in input_plugins_to_be_updated:
        print("Updating plugin {} for service {}".format(p['name'], api_name))
        try:
            saved_plugin_id = [sp["id"] for sp in saved_plugins if sp["name"] == p["name"]][0]
            p["id"] = saved_plugin_id
            json_request("PATCH", "{}/{}".format(plugins_url, saved_plugin_id), p)
        except Exception as e:
            error_msg = str(e)
            if hasattr(e, 'read'):
                try:
                    error_msg = e.read()
                except:
                    pass
            print("ERROR: Failed to update plugin {} for service {}: {}".format(p['name'], api_name, error_msg))
            print("ERROR: Plugin config was: {}".format(json.dumps(p, indent=2)))
    for sp in saved_plugins_to_be_deleted:
        print("Deleting plugin {} for service {}".format(sp['name'], api_name))
        try:
            json_request("DELETE", "{}/{}".format(plugins_url, sp['id']), "")
        except Exception as e:
            print("Warning: Failed to delete plugin {}: {}".format(sp['name'], e))

def _sanitized_api_data(api):
    keys_to_ignore = ['plugins']
    return {k: api[k] for k in api if k not in keys_to_ignore}

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description='Configure kong apis')
    parser.add_argument('apis_file_path', help='Path of the json file containing apis data')
    parser.add_argument('--kong-admin-api-url', help='Admin url for kong', default='http://localhost:8001')
    args = parser.parse_args()
    with open(args.apis_file_path) as apis_file:
        input_apis = json.load(apis_file)
        try:
            save_apis(args.kong_admin_api_url, input_apis)
        except requests.HTTPError as e:
            print(e.response.text)
            raise
