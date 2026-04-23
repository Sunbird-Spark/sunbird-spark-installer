#!/bin/bash
set -e

echo "Starting Keycloak credentials update..."

# Install dependencies
apt-get update && apt-get install -y python3 python3-pip
pip3 install --no-cache-dir psycopg2-binary

case $STORAGE_TYPE in
    "azure")
        pip3 install --no-cache-dir azure-storage-blob
        ;;
    "gcp")
        pip3 install --no-cache-dir google-cloud-storage
        ;;
    "aws")
        pip3 install --no-cache-dir boto3
        ;;
esac

# Run the keycloak credentials update script
python3 /scripts/update_keycloak_credentials.py

echo "Keycloak credentials update completed!"
