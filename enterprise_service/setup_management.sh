#!/bin/bash
# =============================================================================
# AWS Setup Script - Management Account (Jenkins & Nexus)
# Account ID: 816683906758
# =============================================================================

set -e

MANAGEMENT_ACCOUNT_ID="816683906758"
REGION="us-east-1"

echo "=== Setting up Management Account for Jenkins & Nexus ==="

# -----------------------------------------------------------------------------
# 1. Create IAM Roles for Jenkins
# -----------------------------------------------------------------------------
echo "Creating IAM role for Jenkins..."

cat > /tmp/jenkins-role-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:*",
        "eks:*",
        "iam:*",
        "s3:*",
        "ecr:*",
        "sts:AssumeRole"
      ],
      "Resource": "*"
    }
  ]
}
EOF

aws iam create-role \
  --role-name "JenkinsRole" \
  --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ec2.amazonaws.com"},"Action":"sts:AssumeRole"}]}' \
  --profile management 2>/dev/null || echo "Jenkins role already exists"

aws iam put-role-policy \
  --role-name "JenkinsRole" \
  --policy-name "JenkinsPolicy" \
  --policy-document file:///tmp/jenkins-role-policy.json \
  --profile management

# -----------------------------------------------------------------------------
# 2. Create IAM Role for Cross-Account Access
# -----------------------------------------------------------------------------
echo "Creating cross-account deployment role..."

cat > /tmp/cross-account-role-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::${MANAGEMENT_ACCOUNT_ID}:role/JenkinsRole"
      },
      "Action": "sts:AssumeRole",
      "Condition": {}
    }
  ]
}
EOF

# Create deployment role in each environment account
for ACCOUNT_ID in "787308165670" "700800570277" "582599081345" "514585225107"; do
  echo "Creating deployment role in account: $ACCOUNT_ID"
  
  aws iam create-role \
    --role-name "DeploymentRole" \
    --assume-role-policy-document "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Principal\":{\"AWS\":\"arn:aws:iam::${MANAGEMENT_ACCOUNT_ID}:role/JenkinsRole\"},\"Action\":\"sts:AssumeRole\"}]}" \
    --profile management 2>/dev/null || echo "Deployment role already exists in $ACCOUNT_ID"
  
  # Attach admin policy for deployment
  aws iam put-role-policy \
    --role-name "DeploymentRole" \
    --policy-name "DeploymentPolicy" \
    --policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":"*","Resource":"*"}]}' \
    --profile management 2>/dev/null || echo "Policy already exists in $ACCOUNT_ID"
done

# -----------------------------------------------------------------------------
# 3. Create ECR Repositories
# -----------------------------------------------------------------------------
echo "Creating ECR repositories in Management account..."

aws ecr create-repository --repository-name "smartie/jenkins-agent" --region $REGION --profile management 2>/dev/null || echo "Repository jenkins-agent already exists"
aws ecr create-repository --repository-name "smartie/nexus" --region $REGION --profile management 2>/dev/null || echo "Repository nexus already exists"

# -----------------------------------------------------------------------------
# 4. Get Management Account ECR Login
# -----------------------------------------------------------------------------
echo "ECR Login command for Management account:"
aws ecr get-login-password --region $REGion --profile management | docker login --username AWS --password-stdin ${MANAGEMENT_ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com

# -----------------------------------------------------------------------------
# 5. Create SSM Parameter for Account IDs
# -----------------------------------------------------------------------------
echo "Creating SSM parameters for environment account IDs..."

aws ssm put-parameter --name "/smartie/account-ids/dev" --value "787308165670" --type String --profile management 2>/dev/null || echo "Parameter dev exists"
aws ssm put-parameter --name "/smartie/account-ids/sit" --value "700800570277" --type String --profile management 2>/dev/null || echo "Parameter sit exists"
aws ssm put-parameter --name "/smartie/account-ids/uat" --value "582599081345" --type String --profile management 2>/dev/null || echo "Parameter uat exists"
aws ssm put-parameter --name "/smartie/account-ids/prod" --value "514585225107" --type String --profile management 2>/dev/null || echo "Parameter prod exists"

echo "=== Management Account Setup Complete ==="
echo ""
echo "Summary:"
echo "- Jenkins Role: arn:aws:iam::${MANAGEMENT_ACCOUNT_ID}:role/JenkinsRole"
echo "- Cross-account roles created in all environment accounts"
echo "- ECR repositories created"
echo "- SSM parameters stored for account IDs"
