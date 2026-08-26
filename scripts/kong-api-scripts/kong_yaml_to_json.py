import yaml
import json
import os
import os.path


def yaml_to_json_file(input_file, output_file, onboarding_type):
    try:
        # Read YAML content from file
        with open(input_file, 'r') as file:
            yaml_content = file.read()

        # Load YAML content
        data = yaml.load(yaml_content, Loader=yaml.FullLoader)
        if onboarding_type == "api":
            kong_apis_data = data.get('kong_apis', data)
            json_data = json.dumps(kong_apis_data, indent=2)
        elif onboarding_type == "consumer":
            kong_consumers_data = data.get('kong_consumers', data)
            for item in kong_consumers_data:
                if 'credential_rsa_public_key' in item:
                    item['credential_rsa_public_key'] = item['credential_rsa_public_key'].replace('\\n', '\n')
            json_data = json.dumps(kong_consumers_data, indent=2)

        # Write JSON content to file. output_file's path is fixed (the Job
        # template that chains this script to kong_apis.py/kong_consumers.py
        # expects it at a known /tmp path), so guard the write itself against
        # a pre-planted symlink instead: O_EXCL fails loudly if something's
        # already there rather than silently following it.
        fd = os.open(output_file, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, 'w') as file:
            file.write(json_data)

        print("Conversion successful. JSON written to '{}'.".format(output_file))
    except Exception as e:
        print("Error: {}".format(e))


input_api_yaml_file = "/config/kong-apis.yaml"
output_api_json_file = "/tmp/kong-apis.json"
input_consumer_yaml_file = "/config/kong-consumers.yaml"
output_consumer_json_file = "/tmp/kong-consumers.json"

if os.path.exists(input_api_yaml_file):
    yaml_to_json_file(input_api_yaml_file, output_api_json_file, "api")
else:
    print("APIs file not found, skip onboarding APIs")

if os.path.exists(input_consumer_yaml_file):
    yaml_to_json_file(input_consumer_yaml_file, output_consumer_json_file, "consumer")
else:
    print("Consumer file not found, skip onboarding consumers")
