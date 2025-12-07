#!/usr/bin/env bash
set -euo pipefail

# -------- CONFIG --------

# Cost Explorer is only in us-east-1
CE_REGION="${CE_REGION:-us-east-1}"

# Your normal AWS region (where S3 bucket lives)
AWS_REGION="${AWS_REGION:-ap-south-1}"

CUR_BUCKET="${CUR_BUCKET:?CUR_BUCKET is required}"  # e.g. dev-cur-billing-bucket
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

# Time period: current month to today (Cost Explorer: End is exclusive)
START_DATE="$(date +%Y-%m-01)"
END_DATE="$(date -d "tomorrow" +%Y-%m-%d)"   # Linux date; Jenkins agents are usually Linux

echo "Querying Cost Explorer for period:"
echo "  Start: $START_DATE"
echo "  End  : $END_DATE"
echo ""

REPORT_JSON="${REPORT_DIR}/ce_costs_${START_DATE}_to_${END_DATE}.json"

aws ce get-cost-and-usage \
  --time-period Start="$START_DATE",End="$END_DATE" \
  --granularity DAILY \
  --metrics "UnblendedCost" "UsageQuantity" \
  --group-by Type=DIMENSION,Key=SERVICE \
  --region "$CE_REGION" \
  > "$REPORT_JSON"

echo "Report saved locally at: $REPORT_JSON"

# You *can* transform JSON -> CSV here using jq if you want.
# For now we just upload JSON as-is.

LATEST_KEY="latest/latest_ce.json"

echo "Uploading latest CE report to s3://${CUR_BUCKET}/${LATEST_KEY}"
aws s3 cp "$REPORT_JSON" "s3://${CUR_BUCKET}/${LATEST_KEY}" --region "$AWS_REGION"

echo "Done. Latest CE report ready at: s3://${CUR_BUCKET}/${LATEST_KEY}"