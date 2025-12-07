#!/usr/bin/env bash
set -euo pipefail

AWS_REGION="${AWS_REGION:-ap-south-1}"
CUR_BUCKET="${CUR_BUCKET:?CUR_BUCKET is required}"
ACCOUNT_ID="${ACCOUNT_ID:?ACCOUNT_ID is required}"

WORK_ROOT="tmp/cur-latest/${ACCOUNT_ID}"
DOWNLOAD_DIR="${WORK_ROOT}/cur"
mkdir -p "$DOWNLOAD_DIR"

echo "======================================"
echo " Preparing LATEST CUR in account: $ACCOUNT_ID"
echo " Region    : $AWS_REGION"
echo " CUR bucket: s3://${CUR_BUCKET}"
echo "======================================"

echo "AWS identity (should be this account):"
aws sts get-caller-identity
echo ""

echo "Syncing CUR from s3://${CUR_BUCKET} to ${DOWNLOAD_DIR}"
aws s3 sync "s3://${CUR_BUCKET}" "$DOWNLOAD_DIR" --region "$AWS_REGION"

echo "Creating latest.zip for account ${ACCOUNT_ID}"
ZIP_PATH="${WORK_ROOT}/latest.zip"

(
  cd "$WORK_ROOT"
  rm -f latest.zip || true
  zip -r latest.zip cur >/dev/null
)

LATEST_KEY="latest/latest.zip"
echo "Uploading latest CUR ZIP to s3://${CUR_BUCKET}/${LATEST_KEY} (overwrite)"
aws s3 cp "$ZIP_PATH" "s3://${CUR_BUCKET}/${LATEST_KEY}" --region "$AWS_REGION"

echo "Done. Latest CUR ready at: s3://${CUR_BUCKET}/${LATEST_KEY}"