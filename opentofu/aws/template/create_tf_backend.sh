#!/bin/bash
set -e

echo "Creating S3 bucket for Terraform backend..."

# Read values from global-values.yaml
REGION=$(yq eval '.global.cloud_storage_region' global-values.yaml)
ENVIRONMENT=$(yq eval '.global.environment' global-values.yaml)
BUILDING_BLOCK=$(yq eval '.global.building_block' global-values.yaml)

# Validate required variables
if [ -z "$REGION" ] || [ "$REGION" = "null" ]; then
    echo "ERROR: cloud_storage_region not set in global-values.yaml"
    exit 1
fi

if [ -z "$ENVIRONMENT" ] || [ "$ENVIRONMENT" = "null" ]; then
    echo "ERROR: environment not set in global-values.yaml"
    exit 1
fi

if [ -z "$BUILDING_BLOCK" ] || [ "$BUILDING_BLOCK" = "null" ]; then
    echo "ERROR: building_block not set in global-values.yaml"
    exit 1
fi

BACKEND_BUCKET="${BUILDING_BLOCK}-${ENVIRONMENT}-tf-state"
echo "Backend bucket name: $BACKEND_BUCKET"
echo "Region: $REGION"

# Check if bucket already exists
if aws s3 ls "s3://$BACKEND_BUCKET" 2>&1 | grep -q 'NoSuchBucket'; then
    echo "Creating S3 bucket: $BACKEND_BUCKET in region $REGION"
    
    # Create bucket
    if [ "$REGION" = "us-east-1" ]; then
        aws s3api create-bucket --bucket "$BACKEND_BUCKET" --region "$REGION"
    else
        aws s3api create-bucket --bucket "$BACKEND_BUCKET" --region "$REGION" \
            --create-bucket-configuration LocationConstraint="$REGION"
    fi
    
    # Enable versioning
    aws s3api put-bucket-versioning --bucket "$BACKEND_BUCKET" \
        --versioning-configuration Status=Enabled
    
    # Enable encryption
    aws s3api put-bucket-encryption --bucket "$BACKEND_BUCKET" \
        --server-side-encryption-configuration '{
            "Rules": [{
                "ApplyServerSideEncryptionByDefault": {
                    "SSEAlgorithm": "AES256"
                },
                "BucketKeyEnabled": true
            }]
        }'
    
    # Block public access
    aws s3api put-public-access-block --bucket "$BACKEND_BUCKET" \
        --public-access-block-configuration \
        "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
    
    echo "S3 bucket created successfully: $BACKEND_BUCKET"
else
    echo "S3 bucket already exists: $BACKEND_BUCKET"
fi

# Export environment variables for Terragrunt
export TERRAFORM_BACKEND_BUCKET="$BACKEND_BUCKET"
export AWS_REGION="$REGION"

# Create tf.sh script for sourcing
cat > tf.sh << EOF
#!/bin/bash
export TERRAFORM_BACKEND_BUCKET="$BACKEND_BUCKET"
export AWS_REGION="$REGION"
EOF

chmod +x tf.sh

echo "Terraform backend configuration complete."
echo "Backend bucket: $BACKEND_BUCKET"
echo "Region: $REGION"
