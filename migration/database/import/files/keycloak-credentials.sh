#!/bin/bash
set -e

echo "Starting Keycloak credentials update..."

# Install dependencies
apt-get update && apt-get install -y python3 python3-pip
pip3 install --no-cache-dir --only-binary :all: psycopg2-binary==2.9.12

case $STORAGE_TYPE in
    "azure")
        pip3 install --no-cache-dir --only-binary :all: azure-storage-blob==12.30.0
        ;;
    "gcp")
        pip3 install --no-cache-dir --only-binary :all: google-cloud-storage==3.13.1
        ;;
    "aws")
        pip3 install --no-cache-dir --only-binary :all: boto3==1.43.80
        ;;
esac

# Run the keycloak credentials update script
python3 /scripts/update_keycloak_credentials.py

echo "Keycloak credentials update completed!"
