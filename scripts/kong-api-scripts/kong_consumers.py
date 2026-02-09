import urllib.request
import urllib.error
import argparse
import json
import jwt

from common import json_request, get_api_plugins, retrying_urlopen

def _consumer_exists(kong_admin_api_url, username):
    consumers_url = "{}/consumers".format(kong_admin_api_url)
    try:
        retrying_urlopen(consumers_url + "/" + username)
        return True
    except urllib.error.HTTPError as e:
        if(e.code == 404):
            return False
        else:
            raise

def _get_consumer(kong_admin_api_url, username):
    consumers_url = "{}/consumers".format(kong_admin_api_url)
    try:
        response = retrying_urlopen(consumers_url + "/" + username)
        consumer = json.loads(response.read().decode('utf-8'))
        return consumer
    except urllib.error.HTTPError as e:
        if(e.code == 404):
            return None
        else:
            raise

def _dict_without_keys(a_dict, keys):
    return dict((key, a_dict[key]) for key in a_dict if key not in keys)

def _ensure_consumer_exists(kong_admin_api_url, consumer):
    username = consumer['username']
    consumers_url = "{}/consumers".format(kong_admin_api_url)
    if not _consumer_exists(kong_admin_api_url, username):
        print("Adding consumer {}".format(username))
        consumer_data = {'username': username}
        json_request("POST", consumers_url, consumer_data)

def save_consumers(kong_admin_api_url, consumers):
    consumers_url = "{}/consumers".format(kong_admin_api_url)
    print(consumers)
    consumers_to_be_present = [consumer for consumer in consumers if consumer['state'] == 'present']
    consumers_to_be_absent = [consumer for consumer in consumers if consumer['state'] == 'absent']

    for consumer in consumers_to_be_absent:
        username = consumer['username']
        if(_consumer_exists(kong_admin_api_url, username)):
            print("Deleting consumer {}".format(username));
            json_request("DELETE", consumers_url + "/" + username, "")

    for consumer in consumers_to_be_present:
        username = consumer['username']
        _ensure_consumer_exists(kong_admin_api_url, consumer)
        _save_groups_for_consumer(kong_admin_api_url, consumer)
        jwt_credential = _get_first_or_create_jwt_credential(kong_admin_api_url, consumer)
        credential_algorithm = jwt_credential['algorithm']
        if credential_algorithm == 'HS256':
            jwt_token = jwt.encode({'iss': jwt_credential['key']}, jwt_credential['secret'], algorithm=credential_algorithm)
            print("JWT token for {} is : {}".format(username, jwt_token))
        if 'print_credentials' in consumer:
            print("Credentials for consumer {}, key: {}, secret: {}".format(username, jwt_credential['key'], jwt_credential['secret']))

        saved_consumer = _get_consumer(kong_admin_api_url, username)
        rate_limits = consumer.get('rate_limits')
        if(rate_limits is not None):
            _save_rate_limits(kong_admin_api_url, saved_consumer, rate_limits)

def _save_rate_limits(kong_admin_api_url, saved_consumer, rate_limits):
    """
    Kong 3.9.1: Save rate-limiting plugin for consumer.
    Plugins are now attached to services, not APIs.
    """
    plugin_name = 'rate-limiting'
    consumer_id = saved_consumer['id']
    consumer_username = saved_consumer['username']
    for rate_limit in rate_limits:
        service_name = rate_limit.get("service") or rate_limit.get("api")  # Support both names
        saved_plugins = get_api_plugins(kong_admin_api_url, service_name)
        rate_limit_plugins = [saved_plugin for saved_plugin in saved_plugins if saved_plugin['name'] == plugin_name]
        rate_limit_plugins_for_this_consumer = [rate_limit_plugin for rate_limit_plugin in rate_limit_plugins if rate_limit_plugin.get('consumer_id') == consumer_id]
        rate_limit_plugin_for_this_consumer = rate_limit_plugins_for_this_consumer[0] if rate_limit_plugins_for_this_consumer else None

        rate_limit_state = rate_limit.get('state', 'present')
        plugins_url = kong_admin_api_url + "/services/" + service_name + "/plugins"
        if rate_limit_state == 'present':
            rate_limit_plugin_data = _dict_without_keys(rate_limit, ['api', 'service', 'state'])
            rate_limit_plugin_data['name'] = plugin_name
            rate_limit_plugin_data['consumer_id'] = consumer_id
            if not rate_limit_plugin_for_this_consumer:
                print("Adding rate_limit for consumer {} for service {}".format(consumer_username, service_name));
                print("rate_limit_plugin_data: {}".format(rate_limit_plugin_data))
                json_request("POST", plugins_url, rate_limit_plugin_data)

            if rate_limit_plugin_for_this_consumer:
                print("Updating rate_limit for consumer {} for service {}".format(consumer_username, service_name));
                json_request("PATCH", plugins_url + "/" + rate_limit_plugin_for_this_consumer["id"], rate_limit_plugin_data)

        elif rate_limit_state == 'absent':
            if rate_limit_plugin_for_this_consumer:
                print("Deleting rate_limit for consumer {} for service {}".format(consumer_username, service_name));
                json_request("DELETE", plugins_url + "/" + rate_limit_plugin_for_this_consumer["id"], "")

def _get_first_or_create_jwt_credential(kong_admin_api_url, consumer):
    username = consumer["username"]
    credential_algorithm = consumer.get('credential_algorithm', 'HS256')
    # CRITICAL FOR KONG 3.0+: ISS field must be explicitly set
    # ISS (Issuer) claim defaults to consumer username if not specified
    credential_iss = consumer.get('credential_iss', username)

    consumer_jwt_credentials_url = kong_admin_api_url + "/consumers/" + username + "/jwt"
    saved_credentials_details = json.loads(retrying_urlopen(consumer_jwt_credentials_url).read().decode('utf-8'))
    saved_credentials = saved_credentials_details["data"]

    # Filter credentials based on algorithm
    saved_credentials_for_algorithm = [
        saved_credential for saved_credential in saved_credentials
        if saved_credential['algorithm'] == credential_algorithm
    ]

    if credential_iss is not None:
        # Kong 3.0+ Change: Look for ISS field, not just key field
        saved_credentials_for_algorithm_and_iss = [
            saved_credential for saved_credential in saved_credentials_for_algorithm
            if saved_credential.get('iss') == credential_iss
        ]
    else:
        saved_credentials_for_algorithm_and_iss = saved_credentials_for_algorithm

    if len(saved_credentials_for_algorithm_and_iss) > 0:
        print("Updating credentials for consumer {} for algorithm {} and iss {}".format(username, credential_algorithm, credential_iss))
        this_credential = saved_credentials_for_algorithm_and_iss[0]
        # Kong 3.9.1: 'iss' field is read-only, cannot be updated via PATCH
        # Only update key, secret, and rsa_public_key
        credential_data = {
            "rsa_public_key": consumer.get('credential_rsa_public_key', this_credential.get("rsa_public_key", '')),
            "key": consumer.get('key', this_credential.get("key", '')),
            "secret": consumer.get('secret', this_credential.get("secret", ''))
        }
        this_credential_url = "{}/{}".format(consumer_jwt_credentials_url, this_credential["id"])
        response = json_request("PATCH", this_credential_url, credential_data)
        jwt_credential = json.loads(response.read().decode('utf-8'))
        return jwt_credential
    else:
        print("Creating jwt credentials for consumer {} with algorithm {} and iss {}".format(username, credential_algorithm, credential_iss))
        # Kong 3.9.1: 'iss' field is read-only and automatically set from 'key'
        # Do NOT send 'iss' in POST request
        credential_data = {
            "algorithm": credential_algorithm,
            "key": credential_iss   # Key will automatically become the ISS value in Kong 3.9.1
        }
        if "key" in consumer and consumer["key"]:
            credential_data["key"] = consumer["key"]
        if "secret" in consumer and consumer["secret"]:
            credential_data["secret"] = consumer["secret"]
        if 'credential_rsa_public_key' in consumer:
            credential_data["rsa_public_key"] = consumer['credential_rsa_public_key']
        if 'credential_iss' in consumer:
            # Use credential_iss as the key value, ISS will be set automatically by Kong
            if "key" not in consumer or not consumer["key"]:
                credential_data["key"] = consumer['credential_iss']
        
        print("\n=== DEBUG: Creating JWT credential ===")
        print("Credential data being sent:", json.dumps(credential_data, indent=2), flush=True)
        print("=======================================\n", flush=True)
        
        try:
            response = json_request("POST", consumer_jwt_credentials_url, credential_data)
            jwt_credential = json.loads(response.read().decode('utf-8'))
            return jwt_credential
        except urllib.error.HTTPError as e:
            if e.code == 409:
                # Credential already exists, fetch and return it
                print(f"  ⚠ Credential already exists for {username}, fetching existing credential")
                saved_credentials_details = json.loads(retrying_urlopen(consumer_jwt_credentials_url).read().decode('utf-8'))
                saved_credentials = saved_credentials_details["data"]
                # Find credential by key
                for cred in saved_credentials:
                    if cred.get('key') == credential_data.get('key'):
                        return cred
                # If not found by key, return first one with matching algorithm
                for cred in saved_credentials:
                    if cred.get('algorithm') == credential_algorithm:
                        return cred
                # Fallback: return first credential
                if saved_credentials:
                    return saved_credentials[0]
            raise

def _save_groups_for_consumer(kong_admin_api_url, consumer):
    """
    Kong 3.9.1: Sync ACL groups for consumer.
    Handles: create, update, delete of group memberships
    """
    username = consumer["username"]
    input_groups = consumer.get("groups", [])
    consumer_acls_url = kong_admin_api_url + "/consumers/" + username + "/acls"
    
    try:
        saved_acls_details = json.loads(retrying_urlopen(consumer_acls_url + "?size=1000").read().decode('utf-8'))
        saved_acls = saved_acls_details["data"]
    except Exception as e:
        print("Warning: Could not fetch ACL groups for consumer {}: {}".format(username, str(e)))
        saved_acls = []
    
    saved_groups = [acl["group"] for acl in saved_acls]
    print("  ✓ Existing groups for consumer {} : {}".format(username, saved_groups))
    print("  ✓ Required groups for consumer {} : {}".format(username, input_groups))
    
    input_groups_to_be_created = [input_group for input_group in input_groups if input_group not in saved_groups]
    saved_groups_to_be_deleted = [saved_group for saved_group in saved_groups if saved_group not in input_groups]

    for input_group in input_groups_to_be_created:
        print("    ✓ Adding group {} for consumer {}".format(input_group, username))
        try:
            json_request("POST", consumer_acls_url, {'group': input_group})
        except Exception as e:
            print("    ✗ Error adding group {}: {}".format(input_group, str(e)))

    for saved_group in saved_groups_to_be_deleted:
        print("    ✓ Deleting group {} for consumer {}".format(saved_group, username))
        try:
            json_request("DELETE", consumer_acls_url + "/" + saved_group, "")
        except Exception as e:
            print("    ✗ Error deleting group {}: {}".format(saved_group, str(e)))

if  __name__ == "__main__":
    parser = argparse.ArgumentParser(description='Configure kong consumers')
    parser.add_argument('consumers_file_path', help='Path of the json file containing consumer data', default="kong-consumers.json")
    parser.add_argument('--kong-admin-api-url', help='Admin url for kong', default='http://localhost:8001')
    args = parser.parse_args()
    with open(args.consumers_file_path) as consumers_file:
        input_consumers = json.load(consumers_file)
        try:
            save_consumers(args.kong_admin_api_url, input_consumers)
        except urllib.error.HTTPError as e:
            error_message = e.read().decode('utf-8')
            print(error_message)
            raise
