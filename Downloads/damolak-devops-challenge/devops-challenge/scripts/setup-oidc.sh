#!/usr/bin/env bash
# Creates the IAM OIDC provider and role that GitHub Actions uses to deploy.
# Run once. Requires: AWS CLI, jq.
# Usage: GITHUB_ORG=myorg GITHUB_REPO=myrepo ./scripts/setup-oidc.sh
set -euo pipefail

GITHUB_ORG="${GITHUB_ORG:?Set GITHUB_ORG to your GitHub username or org}"
GITHUB_REPO="${GITHUB_REPO:?Set GITHUB_REPO to your repository name}"
ROLE_NAME="${ROLE_NAME:-damolak-github-actions-role}"
REGION="${AWS_REGION:-eu-west-1}"

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
OIDC_URL="https://token.actions.githubusercontent.com"
OIDC_ARN="arn:aws:iam::${ACCOUNT_ID}:oidc-provider/token.actions.githubusercontent.com"

echo "==> Setting up GitHub Actions OIDC (account: $ACCOUNT_ID, region: $REGION)"
echo "    Repo: $GITHUB_ORG/$GITHUB_REPO"

#  OIDC provider ─
if aws iam get-open-id-connect-provider --open-id-connect-provider-arn "$OIDC_ARN" 2>/dev/null; then
  echo "    OIDC provider already exists — skipping"
else
  echo "    Creating OIDC provider..."
  THUMBPRINT=$(openssl s_client -connect token.actions.githubusercontent.com:443 \
    -showcerts </dev/null 2>/dev/null \
    | openssl x509 -fingerprint -noout -sha1 \
    | sed 's/.*=//' | tr -d ':' | tr '[:upper:]' '[:lower:]')

  aws iam create-open-id-connect-provider \
    --url "$OIDC_URL" \
    --client-id-list "sts.amazonaws.com" \
    --thumbprint-list "$THUMBPRINT"
  echo "    OIDC provider created"
fi

#  IAM role 
TRUST_POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "$OIDC_ARN"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:${GITHUB_ORG}/${GITHUB_REPO}:*"
        },
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        }
      }
    }
  ]
}
EOF
)

if aws iam get-role --role-name "$ROLE_NAME" 2>/dev/null; then
  echo "    IAM role '$ROLE_NAME' already exists — skipping"
else
  echo "    Creating IAM role '$ROLE_NAME'..."
  aws iam create-role \
    --role-name "$ROLE_NAME" \
    --assume-role-policy-document "$TRUST_POLICY" \
    --description "Used by GitHub Actions to deploy via OIDC"

  # Attach policies needed for Terraform to provision the full stack
  for policy in \
    "arn:aws:iam::aws:policy/AmazonECS_FullAccess" \
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryFullAccess" \
    "arn:aws:iam::aws:policy/CloudWatchFullAccess"; do
    aws iam attach-role-policy --role-name "$ROLE_NAME" --policy-arn "$policy"
  done

  # Inline policy for VPC, IAM, S3, DynamoDB (Terraform needs these)
  aws iam put-role-policy \
    --role-name "$ROLE_NAME" \
    --policy-name "TerraformDeployPolicy" \
    --policy-document '{
      "Version": "2012-10-17",
      "Statement": [
        {"Effect":"Allow","Action":["ec2:*","iam:*","s3:*","dynamodb:*","elasticloadbalancing:*","application-autoscaling:*","logs:*","sns:*"],"Resource":"*"}
      ]
    }'

  echo "    IAM role created and policies attached"
fi

ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME}"
echo ""
echo "==> OIDC setup complete. Add this secret to GitHub:"
echo "    Settings → Secrets → Actions → New repository secret"
echo "    Name:  AWS_ROLE_ARN"
echo "    Value: $ROLE_ARN"
