#!/usr/bin/env bash
# Bootstraps the Terraform remote state backend (S3 + DynamoDB).
# Run once before the first `terraform apply`. Safe to re-run — checks existence first.
set -euo pipefail

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET="damolak-terraform-state-${ACCOUNT_ID}"
TABLE="damolak-terraform-locks"
REGION="${AWS_REGION:-eu-west-1}"

echo "==> Bootstrapping Terraform state backend (region: $REGION)"

#  S3 bucket 
if aws s3api head-bucket --bucket "$BUCKET" --region "$REGION" 2>/dev/null; then
  echo "    S3 bucket '$BUCKET' already exists — skipping"
else
  echo "    Creating S3 bucket '$BUCKET'..."
  if [ "$REGION" = "us-east-1" ]; then
    aws s3api create-bucket --bucket "$BUCKET" --region "$REGION"
  else
    aws s3api create-bucket \
      --bucket "$BUCKET" \
      --region "$REGION" \
      --create-bucket-configuration LocationConstraint="$REGION"
  fi

  aws s3api put-bucket-versioning \
    --bucket "$BUCKET" \
    --versioning-configuration Status=Enabled

  aws s3api put-bucket-encryption \
    --bucket "$BUCKET" \
    --server-side-encryption-configuration \
    '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

  aws s3api put-public-access-block \
    --bucket "$BUCKET" \
    --public-access-block-configuration \
    "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

  echo "    S3 bucket created with versioning, encryption, and public access blocked"
fi

#  DynamoDB lock table ─
if aws dynamodb describe-table --table-name "$TABLE" --region "$REGION" 2>/dev/null; then
  echo "    DynamoDB table '$TABLE' already exists — skipping"
else
  echo "    Creating DynamoDB table '$TABLE'..."
  aws dynamodb create-table \
    --table-name "$TABLE" \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region "$REGION"

  aws dynamodb wait table-exists --table-name "$TABLE" --region "$REGION"
  echo "    DynamoDB table created"
fi

echo ""
echo "==> State backend ready. You can now run:"
echo "    cd terraform/environments/prod"
echo "    cp terraform.tfvars.example terraform.tfvars  # fill in your values"
echo "    terraform init"
echo "    terraform plan"
