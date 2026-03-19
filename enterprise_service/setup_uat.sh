#!/bin/bash
# =============================================================================
# AWS Setup Script - UAT Environment
# Account ID: 582599081345
# =============================================================================

set -e

ACCOUNT_ID="582599081345"
ACCOUNT_NAME="uat"
REGION="us-east-1"

echo "=== Setting up UAT Environment (Account: $ACCOUNT_ID) ==="

# Configure AWS profile for UAT
aws configure set aws_access_key_id "" --profile uat 2>/dev/null || true
aws configure set aws_secret_access_key "" --profile uat 2>/dev/null || true
aws configure set region $REGION --profile uat

# -----------------------------------------------------------------------------
# 1. Create EKS Cluster for UAT
# -----------------------------------------------------------------------------
echo "Creating EKS cluster for UAT..."

CLUSTER_NAME="smartie-uat-eks"

if ! aws eks describe-cluster --name $CLUSTER_NAME --region $REGION --profile uat 2>/dev/null; then
    echo "Creating EKS cluster: $CLUSTER_NAME"
    aws eks create-cluster \
        --name $CLUSTER_NAME \
        --region $REGION \
        --profile uat \
        --kubernetes-version "1.29" \
        --role-arn "arn:aws:iam::${ACCOUNT_ID}:role/EKSMasterRole" \
        --resources-vpc-config subnetIds=[],endpointPublicAccess=true,endpointPrivateAccess=false \
        2>/dev/null || echo "Cluster creation initiated"
else
    echo "EKS cluster $CLUSTER_NAME already exists"
fi

# -----------------------------------------------------------------------------
# 2. Create S3 Bucket for Documents
# -----------------------------------------------------------------------------
echo "Creating S3 bucket for UAT..."

BUCKET_NAME="smartie-uat-docs-${ACCOUNT_ID}"

aws s3 mb s3://${BUCKET_NAME} --region $REGION --profile uat 2>/dev/null || echo "Bucket already exists"

aws s3api put-bucket-versioning \
    --bucket $BUCKET_NAME \
    --versioning-configuration Status=Enabled \
    --profile uat

# -----------------------------------------------------------------------------
# 3. Create SQS Queue
# -----------------------------------------------------------------------------
echo "Creating SQS queue for UAT..."

QUEUE_NAME="smartie-indexing-queue-uat"
QUEUE_URL="https://sqs.${REGION}.amazonaws.com/${ACCOUNT_ID}/${QUEUE_NAME}"

aws sqs create-queue \
    --queue-name $QUEUE_NAME \
    --region $REGION \
    --profile uat 2>/dev/null || echo "Queue already exists"

QUEUE_URL=$(aws sqs get-queue-url --queue-name $QUEUE_NAME --region $REGION --profile uat --query 'QueueUrl' --output text)

# Configure S3 event notification
aws sqs set-queue-attributes \
    --queue-url $QUEUE_URL \
    --attributes '{"Policy":"{\"Version\":\"2012-10-17\",\"Statement\":[{\"Sid\":\"AllowS3\",\"Effect\":\"Allow\",\"Principal\":\"*\",\"Action\":\"sqs:SendMessage\",\"Resource\":\"arn:aws:sqs:'${REGION}':'${ACCOUNT_ID}':${QUEUE_NAME}\",\"Condition\":{\"ArnLike\":{\"aws:SourceArn\":\"arn:aws:s3:::'${BUCKET_NAME}'\"}}}]}"}' \
    --profile uat

# -----------------------------------------------------------------------------
# 4. Create ECR Repository
# -----------------------------------------------------------------------------
echo "Creating ECR repository for UAT..."

aws ecr create-repository --repository-name "smartie/uat" --region $REGION --profile uat 2>/dev/null || echo "Repository already exists"

# -----------------------------------------------------------------------------
# 5. Create IAM Role for EKS Pods
# -----------------------------------------------------------------------------
echo "Creating IAM role for EKS pods..."

aws iam create-role \
    --role-name "SmartiePodRole" \
    --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"eks.amazonaws.com"},"Action":"sts:AssumeRole"}]}' \
    --profile uat 2>/dev/null || echo "Pod role already exists"

aws iam attach-role-policy \
    --role-name "SmartiePodRole" \
    --policy-arn "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy" \
    --profile uat 2>/dev/null || true

aws iam attach-role-policy \
    --role-name "SmartiePodRole" \
    --policy-arn "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy" \
    --profile uat 2>/dev/null || true

aws iam attach-role-policy \
    --role-name "SmartiePodRole" \
    --policy-arn "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly" \
    --profile uat 2>/dev/null || true

echo "=== UAT Environment Setup Complete ==="
echo ""
echo "Summary for UAT:"
echo "- EKS Cluster: $CLUSTER_NAME"
echo "- S3 Bucket: $BUCKET_NAME"
echo "- SQS Queue: $QUEUE_URL"
echo "- Account ID: $ACCOUNT_ID"
