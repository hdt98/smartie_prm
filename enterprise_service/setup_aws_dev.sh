#!/bin/bash
# =============================================================================
# SMARTIE PRM - AWS Dev Environment Setup
# Creates SQS queue and configures S3 event notifications
# =============================================================================
set -euo pipefail

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET="smartie-dev-docs-${ACCOUNT_ID}"
QUEUE_NAME="smartie-indexing-queue"
REGION="us-east-1"

echo "=== Setting up AWS Dev Infrastructure ==="

# 0. Create S3 Dev Bucket
echo "[0/4] Creating S3 Dev Bucket: $BUCKET ..."
if ! aws s3api head-bucket --bucket "$BUCKET" 2>/dev/null; then
  aws s3 mb "s3://$BUCKET" --region "$REGION"
fi

# 1. Create SQS Queue
echo "[1/4] Creating SQS queue: $QUEUE_NAME ..."
QUEUE_URL=$(aws sqs create-queue \
  --queue-name "$QUEUE_NAME" \
  --region "$REGION" \
  --attributes '{"VisibilityTimeout":"300","MessageRetentionPeriod":"86400"}' \
  --query 'QueueUrl' \
  --output text)
echo "  Queue URL: $QUEUE_URL"

# 2. Get Queue ARN
echo "[2/4] Getting queue ARN..."
QUEUE_ARN=$(aws sqs get-queue-attributes \
  --queue-url "$QUEUE_URL" \
  --attribute-names QueueArn \
  --region "$REGION" \
  --query 'Attributes.QueueArn' \
  --output text)
echo "  Queue ARN: $QUEUE_ARN"

# 3. Set SQS policy to allow S3 to send messages
echo "[3/4] Setting SQS policy for S3 access..."
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowS3ToSendMessage",
      "Effect": "Allow",
      "Principal": {"Service": "s3.amazonaws.com"},
      "Action": "sqs:SendMessage",
      "Resource": "$QUEUE_ARN",
      "Condition": {
        "ArnEquals": {
          "aws:SourceArn": "arn:aws:s3:::$BUCKET"
        }
      }
    }
  ]
}
EOF
)
aws sqs set-queue-attributes \
  --queue-url "$QUEUE_URL" \
  --attributes "{\"Policy\": $(echo "$POLICY" | jq -c '.' | jq -Rs '.')}" \
  --region "$REGION"

# 4. Configure S3 bucket event notifications
echo "[4/4] Configuring S3 event notifications..."
NOTIFICATION_CONFIG=$(cat <<EOF
{
  "QueueConfigurations": [
    {
      "QueueArn": "$QUEUE_ARN",
      "Events": ["s3:ObjectCreated:*"],
      "Filter": {
        "Key": {
          "FilterRules": [
            {"Name": "prefix", "Value": "documents/"}
          ]
        }
      }
    }
  ]
}
EOF
)
aws s3api put-bucket-notification-configuration \
  --bucket "$BUCKET" \
  --notification-configuration "$NOTIFICATION_CONFIG" \
  --region "$REGION"

echo ""
echo "=== Setup Complete ==="
echo ""
echo "Add this to your .env files:"
echo "  SQS_QUEUE_URL=$QUEUE_URL"
echo "  QDRANT_HOST=localhost"
echo "  QDRANT_PORT=6333"
echo "  QDRANT_COLLECTION=smartie_enterprise"
