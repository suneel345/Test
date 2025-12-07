#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Prepare latest Cost Explorer (Billing API) report for account
# - Runs inside a single AWS account (dev/dev2/qa/prod)
# - Uses Cost Explorer API in us-east-1
# - Writes ONE "latest" report to that account's S3 bucket
#
# Expected env vars:
#   CE_REGION   (optional, default: us-east-1)
#   AWS_REGION  (optional, default: ap-south-1)
#   CUR_BUCKET  (required)  e.g. dev-cur-billing-bucket
#   ACCOUNT_ID  (required)  e.g. 222222222222
# ============================================================

# -------- CONFIG --------

# Cost Explorer API lives in us-east-1
CE_REGION="${CE_REGION:-us-east-1}"

# Your normal AWS region (where S3 bucket exists)
AWS_REGION="${AWS_REGION:-ap-south-1}"

CUR_BUCKET="${CUR_BUCKET:?CUR_BUCKET is required}"   # e.g. dev-cur-billing-bucket
ACCOUNT_ID="${ACCOUNT_ID:?ACCOUNT_ID is required}"

WORK_ROOT="tmp/ce-latest/${ACCOUNT_ID}"
REPORT_DIR="${WORK_ROOT}/report"
mkdir -p "$REPORT_DIR"

echo "======================================"
echo " Preparing LATEST CE report via Billing API"
echo " Account     : $ACCOUNT_ID"
echo " CE Region   : $CE_REGION"
echo " S3 Region   : $AWS_REGION"
echo " CUR Bucket  : s3://${CUR_BUCKET}"
echo "======================================"

echo "AWS identity (should be this same account):"
aws sts get-caller-identity --region "$AWS_REGION"
echo ""

# -------- TIME WINDOW (MTD up to yesterday) --------
# AWS Cost Explorer:
#   - Start: inclusive
#   - End  : exclusive
#
# Example if today = 2025-12-08
#   START_DATE  = 2025-12-01
#   END_DATE    = 2025-12-08  (exclusive)
#   YESTERDAY   = 2025-12-07  (inclusive last day of data)
#
START_DATE="$(date +%Y-%m-01)"
END_DATE="$(date +%Y-%m-%d)"             # today = exclusive bound for CE
YESTERDAY="$(date -d "yesterday" +%Y-%m-%d)"

echo "Querying Cost Explorer for actual billing days:"
echo "  Covered (inclusive) : $START_DATE → $YESTERDAY"
echo "  End (CE exclusive)  : $END_DATE"
echo ""

REPORT_JSON="${REPORT_DIR}/ce_costs_${START_DATE}_to_${YESTERDAY}.json"

# -------- CE API CALL --------
echo "Calling Cost Explorer API..."

aws ce get-cost-and-usage \
  --time-period Start="$START_DATE",End="$END_DATE" \
  --granularity DAILY \
  --metrics "UnblendedCost" "UsageQuantity" \
  --group-by Type=DIMENSION,Key=SERVICE \
  --region "$CE_REGION" \
  > "$REPORT_JSON"

echo "Report saved locally at: $REPORT_JSON"

# -------- UPLOAD TO S3 (no history, only latest) --------
# We keep just ONE latest file per account in its own bucket.
# Infra account will take care of all history.
LATEST_KEY="latest/latest_ce.json"

echo "Uploading latest CE report to: s3://${CUR_BUCKET}/${LATEST_KEY}"
aws s3 cp "$REPORT_JSON" "s3://${CUR_BUCKET}/${LATEST_KEY}" --region "$AWS_REGION"

echo "Done. Latest CE report ready at: s3://${CUR_BUCKET}/${LATEST_KEY}"