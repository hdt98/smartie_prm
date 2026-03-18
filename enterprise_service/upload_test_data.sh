#!/bin/bash
# =============================================================================
# Upload test documents from tvpl_corpus to S3
# This triggers S3 event notifications → SQS → Indexing Worker
# =============================================================================
set -euo pipefail

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET="smartie-dev-docs-${ACCOUNT_ID}"
SOURCE_DIR="$HOME/Documents/tvpl_corpus/docs"
S3_PREFIX="documents"

# Test document folders
FOLDERS=(672539 690644 690959 692667 692699 692993 692994 694199 696489 696881)

echo "=== Uploading test data to S3 ==="
echo "Source: $SOURCE_DIR"
echo "Target: s3://$BUCKET/$S3_PREFIX/"
echo ""

for folder in "${FOLDERS[@]}"; do
  if [ -d "$SOURCE_DIR/$folder" ]; then
    echo "Uploading $folder ..."
    aws s3 sync "$SOURCE_DIR/$folder" "s3://$BUCKET/$S3_PREFIX/$folder/" --quiet
  else
    echo "SKIP: $SOURCE_DIR/$folder not found"
  fi
done

echo ""
echo "=== Upload Complete ==="
echo "Uploaded ${#FOLDERS[@]} document folders."
echo "The indexing worker should now pick up SQS events."
