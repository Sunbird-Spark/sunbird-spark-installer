try:
    # Python 3
    import urllib.request as urllib2
except ImportError:
    # Python 2
    import urllib2

import json, logging
from retry import retry

logging.basicConfig()

# Due to issue https://github.com/Mashape/kong/issues/1912
# We can't loop through all apis page by page
# Hence this work around which fetches apis with page size limited to max_page_size
# max_page_size ensures we don't bring down DB by fetching lot of rows
# If we reach a state we have more apis than max_page_size,
# Increase value of max_page_size judiciously
def get_apis(kong_admin_api_url):
    max_page_size = 1000
    apis_url_with_size_limit = "{}/services?size={}".format(kong_admin_api_url, max_page_size)
    apis_response = json.loads(retrying_urlopen(apis_url_with_size_limit).read())
    
    # Kong 3.9.1 response format: direct array or with 'data' field
    if isinstance(apis_response, list):
        # Direct array response
        total_apis = len(apis_response)
        return apis_response
    elif isinstance(apis_response, dict) and 'data' in apis_response:
        # Paginated response with 'data' field
        total_apis = apis_response.get("total", len(apis_response["data"]))
        if total_apis > max_page_size:
            raise Exception("There are {} services existing in system which is more than max_page_size={}. Please increase max_page_size in ansible/kong_apis.py if this is expected".format(total_apis, max_page_size))
        return apis_response["data"]
    else:
        # Unexpected format
        print("DEBUG: apis_response = {}".format(apis_response))
        raise Exception("Unexpected API response format from Kong")

def get_api_plugins(kong_admin_api_url, api_name):
    get_plugins_max_page_size = 1000
    api_pugins_url = "{}/services/{}/plugins".format(kong_admin_api_url, api_name)
    get_api_plugins_url = "{}?size={}".format(api_pugins_url, get_plugins_max_page_size)
    saved_api_details = json.loads(retrying_urlopen(get_api_plugins_url).read())
    
    # Kong 3.9.1 response format: direct array or with 'data' field
    if isinstance(saved_api_details, list):
        # Direct array response
        return saved_api_details
    elif isinstance(saved_api_details, dict) and 'data' in saved_api_details:
        # Paginated response with 'data' field
        return saved_api_details["data"]
    else:
        # Unexpected format
        print("DEBUG: saved_api_details = {}".format(saved_api_details))
        raise Exception("Unexpected plugins API response format from Kong")


def json_request(method, url, data=None):
    request_body = json.dumps(data) if data is not None else None
    request = urllib2.Request(url, request_body)
    if data:
        request.add_header('Content-Type', 'application/json')
    request.get_method = lambda: method
    response = retrying_urlopen(request)
    return response

@retry(exceptions=urllib2.URLError, tries=5, delay=2, backoff=2)
def retrying_urlopen(*args, **kwargs):
    return urllib2.urlopen(*args, **kwargs)