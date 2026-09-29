import argparse, sys
from collections import OrderedDict
import csv
import os
import yaml

def safe_join(base_dir, *parts):
    """os.path.join, but refuses to build a path that escapes base_dir --
    guards apis_csv_file_path against a faulty or malicious CLI argument
    walking the read outside the directory this script is run from."""
    candidate = os.path.realpath(os.path.join(base_dir, *parts))
    base = os.path.realpath(base_dir)
    if os.path.commonpath([candidate, base]) != base:
        raise ValueError(f"Refusing to access outside {base!r}: {candidate!r}")
    return candidate

def setup_yaml():
  """ https://stackoverflow.com/a/31609484/69362 """
  represent_dict_order = lambda self, data:  self.represent_mapping('tag:yaml.org,2002:map', data.items())
  yaml.add_representer(OrderedDict, represent_dict_order)

def convert_csv_to_yaml(apis_csv_file):
    """Convert CSV to Kong 3.9.1 YAML format with services and routes"""
    reader = csv.DictReader(apis_csv_file, delimiter=',')
    apis = []
    for row in reader:
        # Kong 3.9.1 format: services with routes
        apis.append(OrderedDict([
            ('name', row['NAME']),
            ('url', row['UPSTREAM PATH']),  # Changed: upstream_url → url (Kong 3.9.1)
            ('routes', [OrderedDict([
                ('paths', [row['REQUEST PATH']]),
                ('strip_path', True)
            ])]),
            ('plugins', [
                OrderedDict([('name', 'jwt')]),
                OrderedDict([('name', 'cors')]),
                "{{ .Values.statsd_pulgin | toYaml | nindent 4 | trim }}",
                # Kong 3.0 Breaking Change: whitelist → allow
                OrderedDict([('name', 'acl'), ('config', OrderedDict([
                    ('allow', [g.strip() for g in row["WHITELIST GROUP"].split(',')])
                ]))]),
                OrderedDict([('name', 'rate-limiting'), ('config', OrderedDict([
                    ('policy', 'local'),
                    ('hour', int(row["RATE LIMIT"])),
                    ('limit_by', row["LIMIT BY"])
                ]))]),
                OrderedDict([('name', 'request-size-limiting'), ('config', OrderedDict([
                    ('allowed_payload_size', row["REQUEST SIZE LIMIT"])
                ]))]),
            ])
        ]))
    yaml.dump(apis, sys.stdout, default_flow_style=False)

if  __name__ == "__main__":
    parser = argparse.ArgumentParser(description='Converts APIs CSV to yaml that can be used in ansible')
    parser.add_argument('apis_csv_file_path', help='Path of the csv file containing apis data')
    args = parser.parse_args()
    setup_yaml()
    with open(safe_join(os.getcwd(), args.apis_csv_file_path)) as apis_csv_file:
        convert_csv_to_yaml(apis_csv_file)
