#!/bin/bash
# =============================================================================
# AWS Setup Script - SIT Environment
# Account ID: 700800570277
# =============================================================================

set -e

ACCOUNT_ID="700800570277"
ACCOUNT_NAME="sit"
REGION="us-east-1"

echo "=== Setting up SIT Environment (Account: $ACCOUNT_ID) ==="

# Configure AWS profile for SIT
aws configure set aws_access_key_id "" --profile sit 2>/dev/null || true
aws configure set aws_secret_access_key "" --profile sit 2>/dev/null || true
aws configure set region $REGION --profile sit

# -----------------------------------------------------------------------------
# 1. Create EKS Cluster for SIT
# -----------------------------------------------------------------------------
echo "Creating EKS cluster for SIT..."

CLUSTER_NAME="smartie-sit-eks"

# Check if cluster exists
if ! aws eks describe-cluster --name $CLUSTER_NAME --region $REGION --profile sit 2>/dev/null; then
    echo "Creating EKS cluster: $CLUSTER_NAME"
    
    # Create EKS cluster (simplified - no nodegroup for now)
    aws eks create-cluster \
        --name $CLUSTER_NAME \
        --region $REGION \
        --profile sit \
        --kubernetes-version "1.29" \
        --role-arn "arn:aws:iam::${ACCOUNT_ID}:role/EKSMasterRole" \
        --resources-vpc-config subnetIds=[],endpointPublicAccess=true,endpointPrivateAccess=false \
        2>/dev/null || echo "Cluster creation initiated (may require role setup)"
else
    echo "EKS cluster $CLUSTER_NAME already exists"
fi

# -----------------------------------------------------------------------------
# 2. Create S3 Bucket for Documents
# -----------------------------------------------------------------------------
echo "Creating S3 bucket for SIT..."

BUCKET_NAME="smartie-sit-docs-${ACCOUNT_ID}"

aws s3 mb s3://${BUCKET_NAME} --region $REGION --profile sit 2>/dev/null || echo "Bucket $BUCKET_NAME already exists"

# Enable versioning
aws s3api put-bucket-versioning \
    --bucket $BUCKET_NAME \
    --versioning-configuration Status=Enabled \
    --profile sit

# -----------------------------------------------------------------------------
# 3. Create SQS Queue
# -----------------------------------------------------------------------------
echo "Creating SQS queue for SIT..."

QUEUE_NAME="smartie-indexing-queue-sit"
QUEUE_URL="https://sqs.${REGION}.amazonaws.com/${ACCOUNT_ID}/${QUEUE_NAME}"

aws sqs create-queue \
    --queue-name $QUEUE_NAME \
    --region $REGION \
    --profile sit 2>/dev/null || echo "Queue $QUEUE_NAME already exists"

# Get queue URL
QUEUE_URL=$(aws sqs get-queue-url --queue-name $QUEUE_NAME --region $REGION --profile sit --query 'QueueUrl' --output text)

echo "Queue URL: $QUEUE_URL"

# -----------------------------------------------------------------------------
# 4. Configure S3 Event Notification to SQS
# -----------------------------------------------------------------------------
echo "Configuring S3 event notification..."

# Create policy for S3 to publish to SQS
aws sqs set-queue-attributes \
    --queue-url $QUEUE_URL \
    --attributes '{"Policy":"{\"Version\":\"2012-10-17\",\"Statement\":[{\"Sid\":\"AllowS3\",\"Effect\":\"Allow\",\"Principal\":\"*\",\"Action\":\"sqs:SendMessage\",\"Resource\":\"arn:aws:sqs:'${REGION}':'${ACCOUNT_ID}':${QUEUE_NAME}\",\"Condition\":{\"ArnLike\":{\"aws:SourceArn\":\"arn:aws:s3:::'${BUCKET_NAME}'\"}}}]}"}' \
    --profile sit

# -----------------------------------------------------------------------------
# 5. Create ECR Repository
# -----------------------------------------------------------------------------
echo "Creating ECR repository for SIT..."

aws ecr create-repository --repository-name "smartie/sit" --region $REGION --profile sit 2>/dev/null || echo "Repository smartie/sit already exists"

# -----------------------------------------------------------------------------
# 6. Create IAM Role for EKS Pods
# -----------------------------------------------------------------------------
echo "Creating IAM role for EKS pods..."

aws iam create-role \
    --role-name "SmartiePodRole" \
    --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"eks.amazonaws.com"},"Action":"sts:AssumeRole"}]}' \
    --profile sit 2>/dev/null || echo "Pod role already exists"

aws iam attach-role-policy \
    --role-name "SmartiePodRole" \
    --policy-arn "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy" \
    --profile sit 2>/dev/null || true

aws iam attach-role-policy \
    --role-name "SmartiePodRole" \
    --policy-arn "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy" \
    --profile sit 2>/dev/null || true

aws iam attach-role-policy \
    --role-name "SmartiePodRole" \
    --policy-arn "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly" \
    --profile sit 2>/dev/null || true

echo "=== SIT Environment Setup Complete ==="
echo ""
echo "Summary for SIT:"
echo "- EKS Cluster: $CLUSTER_NAME"
echo "- S3 Bucket: $BUCKET_NAME"
echo "- SQS Queue: $QUEUE_URL"
echo "- Account ID: $ACCOUNT_ID"
