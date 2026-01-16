import argparse
import json
import requests
import jwt
from common import json_request, get_api_plugins, retrying_urlopen

try:
    string_types = basestring  # Python 2
except NameError:
    string_types = str  # Python 3

# ---------------- Consumer helpers ----------------
def _consumer_exists(kong_admin_api_url, username):
    consumers_url = "{}/consumers".format(kong_admin_api_url)
    try:
        retrying_urlopen("{}/{}".format(consumers_url, username))
        return True
    except Exception as e:
        if hasattr(e, 'code') and e.code == 404:
            return False
        else:
            raise

def _get_consumer(kong_admin_api_url, username):
    consumers_url = "{}/consumers".format(kong_admin_api_url)
    try:
        response = retrying_urlopen("{}/{}".format(consumers_url, username))
        return json.loads(response.read())
    except Exception as e:
        if hasattr(e, 'code') and e.code == 404:
            return None
        else:
            raise

def _dict_without_keys(a_dict, keys):
    return {key: a_dict[key] for key in a_dict if key not in keys}

def _ensure_consumer_exists(kong_admin_api_url, consumer):
    username = consumer['username']
    consumers_url = "{}/consumers".format(kong_admin_api_url)
    if not _consumer_exists(kong_admin_api_url, username):
        print("Adding consumer {}".format(username))
        consumer_data = {'username': username}
        json_request("POST", consumers_url, consumer_data)

# ---------------- JWT helpers ----------------
def _get_first_or_create_jwt_credential(kong_admin_api_url, consumer):
    username = consumer["username"]
    credential_algorithm = consumer.get('credential_algorithm', 'HS256')
    credential_iss = consumer.get('credential_iss')
    consumer_jwt_credentials_url = "{}/consumers/{}/jwt".format(kong_admin_api_url, username)

    saved_credentials = json.loads(retrying_urlopen(consumer_jwt_credentials_url).read())["data"]

    # HS256 without credential_iss: patch first HS256 credential
    if credential_algorithm == 'HS256' and not credential_iss:
        for saved_credential in saved_credentials:
            if saved_credential['algorithm'] == 'HS256':
                credential_data = {
                    "key": consumer.get('key', saved_credential.get('key', username)),
                    "secret": consumer.get('secret', saved_credential.get('secret', ''))
                }
                url = "{}/{}".format(consumer_jwt_credentials_url, saved_credential['id'])
                jwt_credential = json.loads(json_request("PATCH", url, credential_data).read())
                return jwt_credential

        # Create new if none exists
        credential_data = {
            "algorithm": "HS256",
            "key": consumer.get('key', username),
            "secret": consumer.get('secret', '')
        }
        jwt_credential = json.loads(json_request("POST", consumer_jwt_credentials_url, credential_data).read())
        return jwt_credential

    # RS256 or HS256 with credential_iss
    filtered = [c for c in saved_credentials if c['algorithm'] == credential_algorithm]
    if credential_iss:
        filtered = [c for c in filtered if c.get('key') == credential_iss]

    if filtered:
        cred = filtered[0]
        credential_data = {
            "rsa_public_key": consumer.get('credential_rsa_public_key', cred.get("rsa_public_key", '')),
            "key": consumer.get('key', cred.get("key", '')),
            "secret": consumer.get('secret', cred.get("secret", ''))
        }
        url = "{}/{}".format(consumer_jwt_credentials_url, cred['id'])
        jwt_credential = json.loads(json_request("PATCH", url, credential_data).read())
        return jwt_credential
    else:
        credential_data = {
            "algorithm": credential_algorithm,
            "key": credential_iss or consumer.get('key'),
        }
        if "secret" in consumer:
            credential_data["secret"] = consumer["secret"]
        if 'credential_rsa_public_key' in consumer:
            credential_data["rsa_public_key"] = consumer['credential_rsa_public_key']
        jwt_credential = json.loads(json_request("POST", consumer_jwt_credentials_url, credential_data).read())
        return jwt_credential

# ---------------- ACL helpers ----------------
def _save_groups_for_consumer(kong_admin_api_url, consumer):
    username = consumer["username"]
    input_groups = consumer["groups"]
    consumer_acls_url = "{}/consumers/{}/acls".format(kong_admin_api_url, username)

    saved_acls_details = json.loads(retrying_urlopen("{}?size=1000".format(consumer_acls_url)).read())
    saved_groups = [acl["group"] for acl in saved_acls_details["data"]]

    # Add missing groups
    for input_group in input_groups:
        if input_group not in saved_groups:
            print("Adding group {} for consumer {}".format(input_group, username))
            json_request("POST", consumer_acls_url, {'group': input_group})

    # Delete extra groups
    for saved_group in saved_groups:
        if saved_group not in input_groups:
            print("Deleting group {} for consumer {}".format(saved_group, username))
            json_request("DELETE", "{}/{}".format(consumer_acls_url, saved_group), "")

# ---------------- Rate Limiting helpers ----------------
def _save_rate_limits(kong_admin_api_url, saved_consumer, rate_limits):
    plugin_name = 'rate-limiting'
    consumer_id = saved_consumer['id']
    consumer_username = saved_consumer['username']

    for rate_limit in rate_limits:
        api_name = rate_limit["api"]
        saved_plugins = get_api_plugins(kong_admin_api_url, api_name)
        existing_plugins = [
            p for p in saved_plugins
            if p['name'] == plugin_name and p.get('consumer_id') == consumer_id
        ]

        state = rate_limit.get('state', 'present')
        api_plugins_url = "{}/services/{}/plugins".format(kong_admin_api_url, api_name)

        plugin_data = _dict_without_keys(rate_limit, ['api', 'state'])
        plugin_data['name'] = plugin_name
        plugin_data['consumer_id'] = consumer_id

        if state == 'present':
            if existing_plugins:
                print("Updating rate_limit for {} on {}".format(consumer_username, api_name))
                json_request("PATCH", "{}/{}".format(api_plugins_url, existing_plugins[0]['id']), plugin_data)
            else:
                print("Adding rate_limit for {} on {}".format(consumer_username, api_name))
                json_request("POST", api_plugins_url, plugin_data)
        elif state == 'absent' and existing_plugins:
            print("Deleting rate_limit for {} on {}".format(consumer_username, api_name))
            json_request("DELETE", "{}/{}".format(api_plugins_url, existing_plugins[0]['id']), "")

# ---------------- Main ----------------
def save_consumers(kong_admin_api_url, consumers):
    consumers_to_be_present = [c for c in consumers if c['state'] == 'present']
    consumers_to_be_absent = [c for c in consumers if c['state'] == 'absent']

    for consumer in consumers_to_be_absent:
        username = consumer['username']
        if _consumer_exists(kong_admin_api_url, username):
            print("Deleting consumer {}".format(username))
            json_request("DELETE", "{}/consumers/{}".format(kong_admin_api_url, username), "")

    for consumer in consumers_to_be_present:
        username = consumer['username']
        _ensure_consumer_exists(kong_admin_api_url, consumer)
        _save_groups_for_consumer(kong_admin_api_url, consumer)
        jwt_credential = _get_first_or_create_jwt_credential(kong_admin_api_url, consumer)

        try:
            token = jwt.encode({'iss': jwt_credential['key']}, jwt_credential['secret'], algorithm=jwt_credential['algorithm'])
            print("JWT token for {}: {}".format(username, token))
        except Exception as e:
            print("Skipping JWT token generation for {} (algorithm: {}): {}".format(username, jwt_credential.get('algorithm', 'unknown'), str(e)))

        if 'rate_limits' in consumer:
            saved_consumer = _get_consumer(kong_admin_api_url, username)
            _save_rate_limits(kong_admin_api_url, saved_consumer, consumer['rate_limits'])

# ---------------- Entry ----------------
if __name__ == "__main__":
    parser = argparse.ArgumentParser(description='Configure Kong consumers')
    parser.add_argument('consumers_file_path', help='Path of the JSON file containing consumer data')
    parser.add_argument('--kong-admin-api-url', default='http://localhost:8001', help='Admin URL for Kong')
    args = parser.parse_args()

    with open(args.consumers_file_path) as f:
        consumers = json.load(f)

    try:
        save_consumers(args.kong_admin_api_url, consumers)
    except requests.HTTPError as e:
        print(e.response.text)
        raise
