import argparse
import json
import csv
import os
from common import get_apis, json_request

def safe_join(base_dir, *parts):
    """os.path.join, but refuses to build a path that escapes base_dir --
    guards report_file_path against a faulty or malicious CLI argument
    walking the write outside the directory this script is run from."""
    candidate = os.path.realpath(os.path.join(base_dir, *parts))
    base = os.path.realpath(base_dir)
    if os.path.commonpath([candidate, base]) != base:
        raise ValueError(f"Refusing to access outside {base!r}: {candidate!r}")
    return candidate

def create_api_report_csv(kong_admin_api_url, report_file_path):
    """Generate report for services on-boarded (Kong 3.9.1)"""
    saved_services = get_apis(kong_admin_api_url)
    with open(safe_join(os.getcwd(), report_file_path), 'w') as csvfile:
        fieldnames = ['Name', 'URL', 'Protocol']
        writer = csv.DictWriter(csvfile, fieldnames=fieldnames)
        writer.writeheader()
        for service in saved_services:
            writer.writerow({
                'Name': service['name'],
                'URL': service.get('url', 'N/A'),
                'Protocol': service.get('protocol', 'http')
            })

if  __name__ == "__main__":
    parser = argparse.ArgumentParser(description='Generate report for APIs on-boarded')
    parser.add_argument('report_file_path', help='Report file path')
    parser.add_argument('--kong-admin-api-url', help='Admin url for kong', default='http://localhost:8001')
    args = parser.parse_args()

    create_api_report_csv(args.kong_admin_api_url, args.report_file_path)
