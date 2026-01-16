import argparse
import sys
from collections import OrderedDict
import csv
import yaml

def setup_yaml():
    """
    Preserve order of dicts when dumping to YAML.
    https://stackoverflow.com/a/31609484/69362
    """
    represent_dict_order = lambda self, data: self.represent_mapping(
        'tag:yaml.org,2002:map', data.items()
    )
    yaml.add_representer(OrderedDict, represent_dict_order)

def convert_csv_to_yaml(apis_csv_file):
    reader = csv.DictReader(apis_csv_file, delimiter=',')
    apis = []

    for row in reader:
        apis.append(OrderedDict([
            ('name', row['NAME']),
            ('paths', [row['REQUEST PATH']]),
            ('upstream_url', row['UPSTREAM PATH']),
            ('strip_path', True),
            ('plugins', [
                # JWT plugin
                OrderedDict([
                    ('name', 'jwt'),
                    ('config', OrderedDict([
                        ('key_claim_name', 'iss'),
                        ('header_names', ['authorization'])
                    ]))
                ]),
                # CORS plugin
                OrderedDict([('name', 'cors')]),
                # StatsD plugin placeholder
                "{{ statsd_plugin }}",
                # ACL plugin
                OrderedDict([
                    ('name', 'acl'),
                    ('config', OrderedDict([
                        ('allow', [row["WHITELIST GROUP"]])
                    ]))
                ]),
                # Rate-limiting plugin
                OrderedDict([
                    ('name', 'rate-limiting'),
                    ('config', OrderedDict([
                        ('policy', 'local'),
                        ('hour', int(row["RATE LIMIT"])),
                        ('limit_by', row["LIMIT BY"])
                    ]))
                ]),
                # Request-size-limiting plugin
                OrderedDict([
                    ('name', 'request-size-limiting'),
                    ('config', OrderedDict([
                        ('allowed_payload_size', row["REQUEST SIZE LIMIT"]),
                        ('size_unit', 'megabytes')
                    ]))
                ])
            ])
        ]))

    yaml.dump(apis, sys.stdout, default_flow_style=False)

if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description='Convert APIs CSV to YAML for Kong 3.9.1'
    )
    parser.add_argument(
        'apis_csv_file_path',
        help='Path to the CSV file containing API definitions'
    )
    args = parser.parse_args()

    setup_yaml()
    with open(args.apis_csv_file_path) as apis_csv_file:
        convert_csv_to_yaml(apis_csv_file)
