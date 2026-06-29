#!/bin/bash
set -euo pipefail

# Check if the global-values.yaml file exists
if [[ ! -f "global-values.yaml" ]]; then
  echo "Error: global-values.yaml file does not exist!"
  exit 1
fi

# Extract values using yq (YAML processor)
if ! command -v yq &> /dev/null; then
  echo "Error: yq is not installed. Please install yq to process YAML files."
  exit 1
fi

# Read values from global-values.yaml
building_block=$(yq '.global.building_block' global-values.yaml)
environment_name=$(yq '.global.environment' global-values.yaml)
region=$(yq '.global.cloud_storage_region' global-values.yaml)

# Validate that the values are extracted correctly
if [[ -z "$building_block" || -z "$environment_name" ]]; then
  echo "Error: Unable to extract values from global-values.yaml"
  exit 1
fi

# Debugging: Print extracted values
echo "Extracted building_block: \"$building_block\""
echo "Extracted environment_name: \"$environment_name\""
echo "Extracted region: \"$region\""

# Get AWS Account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Construct resource names
BUCKET_NAME="${environment_name}-tfstate-${ACCOUNT_ID}"
DYNAMODB_TABLE="${environment_name}-tfstate-lock"

# Debugging: Print generated names
echo "BUCKET_NAME: $BUCKET_NAME"
echo "DYNAMODB_TABLE: $DYNAMODB_TABLE"
echo "REGION: $region"
echo "ACCOUNT_ID: $ACCOUNT_ID"

# Create the S3 bucket for OpenTofu state
if aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
  echo "S3 bucket '$BUCKET_NAME' already exists — skipping creation."
else
  if [[ "$region" == "us-east-1" ]]; then
    # us-east-1 does not accept LocationConstraint
    aws s3api create-bucket \
      --bucket "$BUCKET_NAME" \
      --region "$region"
  else
    aws s3api create-bucket \
      --bucket "$BUCKET_NAME" \
      --region "$region" \
      --create-bucket-configuration LocationConstraint="$region"
  fi
  echo "Created S3 bucket: $BUCKET_NAME"
fi

# Enable versioning on the state bucket
aws s3api put-bucket-versioning \
  --bucket "$BUCKET_NAME" \
  --versioning-configuration Status=Enabled

# Block all public access on the state bucket
aws s3api put-public-access-block \
  --bucket "$BUCKET_NAME" \
  --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

# Enable server-side encryption on the state bucket
aws s3api put-bucket-encryption \
  --bucket "$BUCKET_NAME" \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "AES256"
      }
    }]
  }'

# Create DynamoDB table for state locking
if aws dynamodb describe-table --table-name "$DYNAMODB_TABLE" --region "$region" 2>/dev/null; then
  echo "DynamoDB table '$DYNAMODB_TABLE' already exists — skipping creation."
else
  aws dynamodb create-table \
    --table-name "$DYNAMODB_TABLE" \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region "$region"
  echo "Created DynamoDB table: $DYNAMODB_TABLE"
fi

# Export OpenTofu backend details to a file
echo "export AWS_OPENTOFU_BACKEND_BUCKET=$BUCKET_NAME" > tf.sh
echo "export AWS_OPENTOFU_BACKEND_REGION=$region" >> tf.sh
echo "export AWS_OPENTOFU_BACKEND_DYNAMODB_TABLE=$DYNAMODB_TABLE" >> tf.sh
echo "export AWS_ACCOUNT_ID=$ACCOUNT_ID" >> tf.sh

echo -e "\nOpenTofu backend setup complete!"
echo -e "Run the following command to set the environment variables:"
echo "source tf.sh"
