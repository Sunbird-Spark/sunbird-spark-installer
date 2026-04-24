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

def _derive_owned_groups(consumers):
    """
    Derive the set of ACL group names that this chart "owns" —
    i.e. the union of ALL groups listed across every consumer in the input file.

    This is used to scope group deletions: only a group that appears in this
    set will ever be removed from a consumer.  Groups added by another chart
    (e.g. an addon that appended 'discussionAccess') are NOT in this set and
    are therefore never touched by this run.
    """
    owned = set()
    for consumer in consumers:
        for group in consumer.get("groups", []):
            owned.add(group)
    return owned

def save_consumers(kong_admin_api_url, consumers, managed_by="core"):
    consumers_url = "{}/consumers".format(kong_admin_api_url)
    
    # Track statistics for the summary
    stats = {
        "consumers": {"created": 0, "deleted": 0, "skipped": 0},
        "credentials": {"created": 0, "updated": 0, "skipped": 0},
        "groups": {"added": 0, "deleted": 0, "skipped": 0},
        "rate_limits": {"created": 0, "updated": 0, "deleted": 0, "skipped": 0}
    }

    # Compute the set of groups this chart is responsible for.
    owned_groups = _derive_owned_groups(consumers)
    
    # Pre-fetch all consumers to show a clean count at the end
    try:
        all_saved_consumers = json.loads(urllib.request.urlopen(consumers_url + "?size=1000").read().decode('utf-8'))
        total_consumers_in_kong = len(all_saved_consumers.get('data', []))
    except:
        total_consumers_in_kong = 0

    consumers_to_be_present = [consumer for consumer in consumers if consumer['state'] == 'present']
    consumers_to_be_absent = [consumer for consumer in consumers if consumer['state'] == 'absent']

    for consumer in consumers_to_be_absent:
        username = consumer['username']
        if(_consumer_exists(kong_admin_api_url, username)):
            print("Deleting consumer {}".format(username))
            json_request("DELETE", consumers_url + "/" + username, None)
            stats["consumers"]["deleted"] += 1

    for consumer in consumers_to_be_present:
        username = consumer['username']
        
        # Check if exists before creating
        if not _consumer_exists(kong_admin_api_url, username):
            _ensure_consumer_exists(kong_admin_api_url, consumer)
            stats["consumers"]["created"] += 1
        else:
            stats["consumers"]["skipped"] += 1
            
        _save_groups_for_consumer(kong_admin_api_url, consumer, owned_groups, stats, managed_by)
        _save_credential_for_consumer(kong_admin_api_url, consumer, stats)

        saved_consumer = _get_consumer(kong_admin_api_url, username)
        rate_limits = consumer.get('rate_limits')
        if(rate_limits is not None):
            _save_rate_limits(kong_admin_api_url, saved_consumer, rate_limits, stats)

    print("\n--- Kong Consumer Onboarding Summary ---")
    print("Number of input consumers   : {}".format(len(consumers)))
    print("Total consumers in Kong     : {}".format(total_consumers_in_kong))
    print("Managed-by label            : {}".format(managed_by))
    print("Owned ACL groups            : {}".format(sorted(owned_groups)))
    print("----------------------------------------\n")

def _save_credential_for_consumer(kong_admin_api_url, consumer, stats):
    """Abstraction for credential management with change detection."""
    _get_first_or_create_jwt_credential(kong_admin_api_url, consumer, stats)

def _save_rate_limits(kong_admin_api_url, saved_consumer, rate_limits, stats):
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
                print("Adding rate_limit for consumer {} for service {}".format(consumer_username, service_name))
                json_request("POST", plugins_url, rate_limit_plugin_data)
                stats["rate_limits"]["created"] += 1
            else:
                # Check for changes in config
                changed = False
                existing_config = rate_limit_plugin_for_this_consumer.get('config', {})
                for key, val in rate_limit_plugin_data.items():
                    if key.startswith('config.'):
                        config_key = key.replace('config.', '')
                        if str(val) != str(existing_config.get(config_key)):
                            changed = True; break
                
                if changed:
                    print("Updating rate_limit for consumer {} for service {}".format(consumer_username, service_name))
                    json_request("PATCH", plugins_url + "/" + rate_limit_plugin_for_this_consumer["id"], rate_limit_plugin_data)
                    stats["rate_limits"]["updated"] += 1
                else:
                    stats["rate_limits"]["skipped"] += 1

        elif rate_limit_state == 'absent':
            if rate_limit_plugin_for_this_consumer:
                print("Deleting rate_limit for consumer {} for service {}".format(consumer_username, service_name))
                json_request("DELETE", plugins_url + "/" + rate_limit_plugin_for_this_consumer["id"], None)
                stats["rate_limits"]["deleted"] += 1

def _get_first_or_create_jwt_credential(kong_admin_api_url, consumer, stats):
    username = consumer["username"]
    credential_algorithm = consumer.get('credential_algorithm', 'HS256')
    credential_iss = consumer.get('credential_iss', username)
    credential_key = consumer.get('key', credential_iss)

    consumer_jwt_credentials_url = kong_admin_api_url + "/consumers/" + username + "/jwt"
    saved_credentials_details = json.loads(retrying_urlopen(consumer_jwt_credentials_url).read().decode('utf-8'))
    saved_credentials = saved_credentials_details["data"]

    # 1. Look for a match by 'key' (this is the most reliable check for Kong 3.x)
    match_by_key = [c for c in saved_credentials if c.get('key') == credential_key]
    
    if not match_by_key:
        # 2. Re-check by algorithm and ISS (legacy search)
        match_by_key = [
            c for c in saved_credentials
            if c.get('algorithm') == credential_algorithm and c.get('iss') == credential_iss
        ]

    if match_by_key:
        this_credential = match_by_key[0]
        
        # Check if change is needed
        new_secret = consumer.get('secret', this_credential.get("secret", ''))
        new_rsa = consumer.get('credential_rsa_public_key', this_credential.get("rsa_public_key", ''))
        
        # Note: key/iss cannot be changed once created in Kong, so we only update secret/rsa
        if new_secret != this_credential.get('secret') or new_rsa != this_credential.get('rsa_public_key'):
            print("Updating credentials for consumer {} (key: {})".format(username, credential_key))
            credential_data = {
                "rsa_public_key": new_rsa,
                "secret": new_secret
            }
            this_credential_url = "{}/{}".format(consumer_jwt_credentials_url, this_credential["id"])
            response = json_request("PATCH", this_credential_url, credential_data)
            jwt_credential = json.loads(response.read().decode('utf-8'))
            stats["credentials"]["updated"] += 1
        else:
            jwt_credential = this_credential
            stats["credentials"]["skipped"] += 1
            
        # Print token for HS256
        if jwt_credential['algorithm'] == 'HS256':
            jwt_token = jwt.encode({'iss': jwt_credential['key']}, jwt_credential['secret'], algorithm='HS256')
            print("JWT token for {} is : {}".format(username, jwt_token))
        if 'print_credentials' in consumer:
            print("Credentials for consumer {}, key: {}, secret: {}".format(username, jwt_credential['key'], jwt_credential['secret']))
            
        return jwt_credential
    else:
        print("Creating jwt credentials for consumer {} with algorithm {} (key: {})".format(username, credential_algorithm, credential_key))
        credential_data = {
            "algorithm": credential_algorithm,
            "key": credential_key
        }
        if "secret" in consumer and consumer["secret"]:
            credential_data["secret"] = consumer["secret"]
        if 'credential_rsa_public_key' in consumer:
            credential_data["rsa_public_key"] = consumer['credential_rsa_public_key']

        try:
            response = json_request("POST", consumer_jwt_credentials_url, credential_data)
            jwt_credential = json.loads(response.read().decode('utf-8'))
            stats["credentials"]["created"] += 1
            
            # Print token for HS256
            if jwt_credential['algorithm'] == 'HS256':
                jwt_token = jwt.encode({'iss': jwt_credential['key']}, jwt_credential['secret'], algorithm='HS256')
                print("JWT token for {} is : {}".format(username, jwt_token))
                
            return jwt_credential
        except urllib.error.HTTPError as e:
            if e.code == 409:
                print(f"  ⚠ Credential key {credential_key} already exists, fetching existing one")
                saved_credentials_details = json.loads(retrying_urlopen(consumer_jwt_credentials_url).read().decode('utf-8'))
                shared_credentials = saved_credentials_details["data"]
                
                for cred in shared_credentials:
                    if cred.get('key') == credential_key:
                        stats["credentials"]["skipped"] += 1
                        if cred['algorithm'] == 'HS256':
                            jwt_token = jwt.encode({'iss': cred['key']}, cred['secret'], algorithm='HS256')
                            print("JWT token for {} is : {}".format(username, jwt_token))
                        return cred
            raise

def _save_groups_for_consumer(kong_admin_api_url, consumer, owned_groups, stats, managed_by="core"):
    """
    Scoped ACL group sync for a consumer.
    """
    username = consumer["username"]
    input_groups = set(consumer.get("groups", []))
    consumer_acls_url = kong_admin_api_url + "/consumers/" + username + "/acls"

    try:
        saved_acls_details = json.loads(retrying_urlopen(consumer_acls_url + "?size=1000").read().decode('utf-8'))
        saved_acls = saved_acls_details["data"]
    except Exception as e:
        print("Warning: Could not fetch ACL groups for consumer {}: {}".format(username, str(e)))
        saved_acls = []

    saved_groups = set(acl["group"] for acl in saved_acls)
    
    # Groups to add: in input but not yet in Kong
    groups_to_add = input_groups - saved_groups

    # Groups to delete: no longer in input AND owned by this chart
    groups_to_delete = (saved_groups - input_groups) & owned_groups
    
    # Groups to skip: in input AND already in Kong
    groups_skipped = input_groups & saved_groups
    stats["groups"]["skipped"] += len(groups_skipped)

    for group in sorted(groups_to_add):
        print("    ✓ Adding group {} for consumer {}".format(group, username))
        try:
            json_request("POST", consumer_acls_url, {'group': group})
            stats["groups"]["added"] += 1
        except Exception as e:
            print("    ✗ Error adding group {}: {}".format(group, str(e)))

    for group in sorted(groups_to_delete):
        print("    ✓ Deleting group {} for consumer {} (owned by {}, no longer in input)".format(group, username, managed_by))
        try:
            json_request("DELETE", consumer_acls_url + "/" + group, None)
            stats["groups"]["deleted"] += 1
        except Exception as e:
            print("    ✗ Error deleting group {}: {}".format(group, str(e)))

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description='Configure kong consumers')
    parser.add_argument(
        'consumers_file_path',
        help='Path of the json file containing consumer data',
        default="kong-consumers.json"
    )
    parser.add_argument(
        '--kong-admin-api-url',
        help='Admin url for kong',
        default='http://localhost:8001'
    )
    parser.add_argument(
        '--managed-by',
        default='core',
        dest='managed_by',
        help=(
            'Ownership label for this run (e.g. "core", "discussion-forum"). '
            'Only ACL groups declared in THIS chart\'s input file will ever be '
            'deleted from consumers. Groups added by other charts are left untouched. '
            'Default: core'
        )
    )
    args = parser.parse_args()
    with open(args.consumers_file_path) as consumers_file:
        input_consumers = json.load(consumers_file)
        try:
            save_consumers(args.kong_admin_api_url, input_consumers, managed_by=args.managed_by)
        except urllib.error.HTTPError as e:
            error_message = e.read().decode('utf-8')
            print(error_message)
            raise
