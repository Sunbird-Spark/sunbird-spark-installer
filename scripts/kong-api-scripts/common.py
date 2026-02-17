import urllib.request
import urllib.error
import urllib.parse
import json
import logging
import time

logging.basicConfig()

# Kong 3.9.1 Upgrade: /apis endpoint replaced with /services
# Services represent backend targets, Routes define how requests are matched
# This function now fetches services instead of deprecated APIs
def get_apis(kong_admin_api_url):
    """Fetch services from Kong 3.9.1 (replaces legacy /apis endpoint)"""
    max_page_size = 1000
    services_url_with_size_limit = "{}/services?size={}".format(kong_admin_api_url, max_page_size)
    services_response = json.loads(retrying_urlopen(services_url_with_size_limit).read().decode('utf-8'))
    
    # Kong 3.x may not include 'total' in response, use actual data length as fallback
    data = services_response.get("data", [])
    total_services = services_response.get("total", len(data))
    
    if(total_services > max_page_size):
        raise Exception("There are {} services existing in system which is more than max_page_size={}. Please increase max_page_size if this is expected".format(total_services, max_page_size))
    else:
       return data

def get_routes(kong_admin_api_url, service_name):
    """Fetch routes for a service in Kong 3.9.1"""
    max_page_size = 100
    routes_url = "{}/services/{}/routes?size={}".format(kong_admin_api_url, service_name, max_page_size)
    routes_response = json.loads(retrying_urlopen(routes_url).read().decode('utf-8'))
    return routes_response["data"]

def get_api_plugins(kong_admin_api_url, service_name):
    """Fetch plugins attached to a service in Kong 3.9.1 (replaces /apis/{id}/plugins)"""
    get_plugins_max_page_size = 100
    # URL encode service name to handle special characters
    encoded_service_name = urllib.parse.quote(service_name, safe='')
    plugins_url = "{}/services/{}/plugins?size={}".format(kong_admin_api_url, encoded_service_name, get_plugins_max_page_size)
    saved_plugins_details = json.loads(retrying_urlopen(plugins_url).read().decode('utf-8'))
    return saved_plugins_details.get("data", [])


def json_request(method, url, data=None):
    request_body = json.dumps(data).encode('utf-8') if data is not None else None
    request = urllib.request.Request(url, request_body)
    if data:
        request.add_header('Content-Type', 'application/json')
    request.get_method = lambda: method
    response = retrying_urlopen(request)
    return response

def retrying_urlopen(url, retry_count=0, data=None):
    """
    Retry logic for Kong 3.9.1 - Python 3 compatible
    Exponential backoff: 2, 4, 8, 16, 32 seconds (max 5 attempts)
    """
    if retry_count < 5:
        try:
            if isinstance(url, str):
                req = urllib.request.Request(url, data=data)
            else:
                req = url
            response = urllib.request.urlopen(req, timeout=10)
            return response
        except urllib.error.HTTPError as e:
            # Capture Kong's error response for debugging
            error_body = ""
            try:
                error_body = e.read().decode('utf-8')
            except:
                pass
            
            # Print error details on first attempt or final failure
            if retry_count == 0 or retry_count >= 4:
                print(f"\n=== HTTP {e.code} ERROR ===", flush=True)
                print(f"URL: {e.url}", flush=True)
                if error_body:
                    print(f"Kong error response: {error_body}", flush=True)
                print(f"==================\n", flush=True)
            
            # Don't retry 4xx client errors (except 429 Too Many Requests)
            # These indicate bad request data, not transient failures
            if 400 <= e.code < 500 and e.code != 429:
                raise
            
            # Retry 5xx server errors and 429
            wait_time = 2 ** retry_count
            if retry_count < 4:
                time.sleep(wait_time)
                return retrying_urlopen(url, retry_count + 1, data)
            else:
                raise
        except urllib.error.URLError as e:
            wait_time = 2 ** retry_count
            if retry_count < 4:
                time.sleep(wait_time)
                return retrying_urlopen(url, retry_count + 1, data)
            else:
                raise