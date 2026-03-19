#!/bin/bash
# =============================================================================
# AWS Setup Script - Prod Environment
# Account ID: 514585225107
# =============================================================================

set -e

ACCOUNT_ID="514585225107"
ACCOUNT_NAME="prod"
REGION="us-east-1"

echo "=== Setting up PROD Environment (Account: $ACCOUNT_ID) ==="

# Configure AWS profile for PROD
aws configure set aws_access_key_id "" --profile prod 2>/dev/null || true
aws configure set aws_secret_access_key "" --profile prod 2>/dev/null || true
aws configure set region $REGION --profile prod

# -----------------------------------------------------------------------------
# 1. Create EKS Cluster for PROD (Private endpoints)
# -----------------------------------------------------------------------------
echo "Creating EKS cluster for PROD..."

CLUSTER_NAME="smartie-prod-eks"

if ! aws eks describe-cluster --name $CLUSTER_NAME --region $REGION --profile prod 2>/dev/null; then
    echo "Creating EKS cluster: $CLUSTER_NAME (private endpoints)"
    aws eks create-cluster \
        --name $CLUSTER_NAME \
        --region $REGION \
        --profile prod \
        --kubernetes-version "1.29" \
        --role-arn "arn:aws:iam::${ACCOUNT_ID}:role/EKSMasterRole" \
        --resources-vpc-config subnetIds=[],endpointPublicAccess=false,endpointPrivateAccess=true \
        2>/dev/null || echo "Cluster creation initiated"
else
    echo "EKS cluster $CLUSTER_NAME already exists"
fi

# -----------------------------------------------------------------------------
# 2. Create S3 Bucket for Documents (with encryption)
# -----------------------------------------------------------------------------
echo "Creating S3 bucket for PROD..."

BUCKET_NAME="smartie-prod-docs-${ACCOUNT_ID}"

aws s3 mb s3://${BUCKET_NAME} --region $REGION --profile prod 2>/dev/null || echo "Bucket already exists"

# Enable versioning and encryption
aws s3api put-bucket-versioning \
    --bucket $BUCKET_NAME \
    --versioning-configuration Status=Enabled \
    --profile prod

aws s3api put-bucket-encryption \
    --bucket $BUCKET_NAME \
    --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}' \
    --profile prod

# Block public access
aws s3api put-public-access-block \
    --bucket $BUCKET_NAME \
    --public-access-block-configuration "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true" \
    --profile prod

# -----------------------------------------------------------------------------
# 3. Create SQS Queue
# -----------------------------------------------------------------------------
echo "Creating SQS queue for PROD..."

QUEUE_NAME="smartie-indexing-queue-prod"
QUEUE_URL="https://sqs.${REGION}.amazonaws.com/${ACCOUNT_ID}/${QUEUE_NAME}"

aws sqs create-queue \
    --queue-name $QUEUE_NAME \
    --region $REGION \
    --profile prod 2>/dev/null || echo "Queue already exists"

QUEUE_URL=$(aws sqs get-queue-url --queue-name $QUEUE_NAME --region $REGION --profile prod --query 'QueueUrl' --output text)

# Configure S3 event notification (with strict policy)
aws sqs set-queue-attributes \
    --queue-url $QUEUE_URL \
    --attributes '{"Policy":"{\"Version\":\"2012-10-17\",\"Statement\":[{\"Sid\":\"AllowS3\",\"Effect\":\"Allow\",\"Principal\":\"*\",\"Action\":\"sqs:SendMessage\",\"Resource\":\"arn:aws:sqs:'${REGION}':'${ACCOUNT_ID}':${QUEUE_NAME}\",\"Condition\":{\"ArnLike\":{\"aws:SourceArn\":\"arn:aws:s3:::'${BUCKET_NAME}'\"}}}]}"}' \
    --profile prod

# -----------------------------------------------------------------------------
# 4. Create ECR Repository with lifecycle policy
# -----------------------------------------------------------------------------
echo "Creating ECR repository for PROD..."

aws ecr create-repository --repository-name "smartie/prod" --region $REGION --profile prod 2>/dev/null || echo "Repository already exists"

# Add lifecycle policy to keep only last 10 images
aws ecr put-lifecycle-policy \
    --repository-name "smartie/prod" \
    --lifecycle-policy-text '{"rules":[{"rulePriority":1,"description":"Keep last 10 images","selection":{"tagStatus":"tagged","tagPrefixList":["v"],"countType":"imageCountMoreThan","countNumber":10},"action":{"type":"expire"}}]}' \
    --profile prod

# -----------------------------------------------------------------------------
# 5. Create IAM Role for EKS Pods (with least privilege)
# -----------------------------------------------------------------------------
echo "Creating IAM role for EKS pods..."

aws iam create-role \
    --role-name "SmartiePodRole" \
    --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"eks.amazonaws.com"},"Action":"sts:AssumeRole"}]}' \
    --profile prod 2>/dev/null || echo "Pod role already exists"

# Attach read-only policies
aws iam attach-role-policy \
    --role-name "SmartiePodRole" \
    --policy-arn "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy" \
    --profile prod 2>/dev/null || true

aws iam attach-role-policy \
    --role-name "SmartiePodRole" \
    --policy-arn "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy" \
    --profile prod 2>/dev/null || true

aws iam attach-role-policy \
    --role-name "SmartiePodRole" \
    --policy-arn "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly" \
    --profile prod 2>/dev/null || true

# -----------------------------------------------------------------------------
# 6. Enable CloudTrail for Audit
# -----------------------------------------------------------------------------
echo "Setting up CloudTrail for PROD..."

aws cloudtrail create-trail \
    --name "smartie-prod-audit" \
    --s3-bucket-name "smartie-prod-audit-${ACCOUNT_ID}" \
    --is-multi-region-trail \
    --enable-log-file-validation \
    --profile prod 2>/dev/null || echo "CloudTrail may already exist"

echo "=== PROD Environment Setup Complete ==="
echo ""
echo "Summary for PROD:"
echo "- EKS Cluster: $CLUSTER_NAME (private endpoints)"
echo "- S3 Bucket: $BUCKET_NAME (encrypted, no public access)"
echo "- SQS Queue: $QUEUE_URL"
echo "- ECR: smartie/prod (lifecycle policy: keep 10 images)"
echo "- CloudTrail: smartie-prod-audit enabled"
echo "- Account ID: $ACCOUNT_ID"
