import argparse
import json
import csv
from common import get_apis, json_request

def create_api_report_csv(kong_admin_api_url, report_file_path):
    """Generate report for services on-boarded (Kong 3.9.1)"""
    saved_services = get_apis(kong_admin_api_url)
    with open(report_file_path, 'w') as csvfile:
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
