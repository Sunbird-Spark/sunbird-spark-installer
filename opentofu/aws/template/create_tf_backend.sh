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

get_bucket_region() {
    local location
    location=$(aws s3api get-bucket-location --bucket "$1" --output text)
    if [ "$location" = "None" ] || [ "$location" = "null" ] || [ -z "$location" ]; then
        echo "us-east-1"
    else
        echo "$location"
    fi
}

BACKEND_BUCKET="${BUILDING_BLOCK}-${ENVIRONMENT}-tf-state"
echo "Backend bucket name: $BACKEND_BUCKET"
echo "Region: $REGION"

# Check if bucket already exists
if aws s3api head-bucket --bucket "$BACKEND_BUCKET" >/dev/null 2>&1; then
    EXISTING_REGION=$(get_bucket_region "$BACKEND_BUCKET")
    if [ "$EXISTING_REGION" != "$REGION" ]; then
        echo "ERROR: S3 bucket $BACKEND_BUCKET exists in $EXISTING_REGION but cloud_storage_region is $REGION"
        echo "Delete the bucket and re-run this script, or update cloud_storage_region to match."
        exit 1
    fi
    echo "S3 bucket already exists: $BACKEND_BUCKET"
else
    echo "Creating S3 bucket: $BACKEND_BUCKET in region $REGION"

    # Retry when the bucket name is still releasing after a recent delete
    CREATE_ATTEMPTS=20
    CREATE_WAIT_SECS=30
    for attempt in $(seq 1 "$CREATE_ATTEMPTS"); do
        CREATE_ERR=$(mktemp)
        if [ "$REGION" = "us-east-1" ]; then
            aws s3api create-bucket --bucket "$BACKEND_BUCKET" --region "$REGION" 2>"$CREATE_ERR" && break
        else
            aws s3api create-bucket --bucket "$BACKEND_BUCKET" --region "$REGION" \
                --create-bucket-configuration LocationConstraint="$REGION" 2>"$CREATE_ERR" && break
        fi
        if grep -qE 'OperationAborted|BucketAlreadyOwnedByYou' "$CREATE_ERR" && [ "$attempt" -lt "$CREATE_ATTEMPTS" ]; then
            if grep -q OperationAborted "$CREATE_ERR"; then
                echo "Bucket name still releasing after delete; retry $attempt/$CREATE_ATTEMPTS in ${CREATE_WAIT_SECS}s..."
            else
                echo "Bucket create already completed; continuing..."
            fi
            sleep "$CREATE_WAIT_SECS"
            if aws s3api head-bucket --bucket "$BACKEND_BUCKET" >/dev/null 2>&1; then
                rm -f "$CREATE_ERR"
                break
            fi
        else
            cat "$CREATE_ERR" >&2
            rm -f "$CREATE_ERR"
            exit 1
        fi
        rm -f "$CREATE_ERR"
    done
    rm -f "$CREATE_ERR"

    CREATED_REGION=$(get_bucket_region "$BACKEND_BUCKET")
    if [ "$CREATED_REGION" != "$REGION" ]; then
        echo "ERROR: S3 bucket $BACKEND_BUCKET was created in $CREATED_REGION instead of $REGION"
        echo "Delete the bucket, wait a few minutes for the name to release, then re-run this script."
        exit 1
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
