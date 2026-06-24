#!/bin/bash

PROJECT_ID="********************************"
OUTPUT_FILE="sa_key_detailed_audit_report.csv"

echo "Generating Detailed Service Account Key Audit Report..."

# Write CSV Header
echo "Service Account,Key ID,Key Type,Created Time,Expiry Time" > $OUTPUT_FILE

# Get all service accounts
SERVICE_ACCOUNTS=$(gcloud iam service-accounts list \
  --project=$PROJECT_ID \
  --format="value(email)")

for SA in $SERVICE_ACCOUNTS
do
  KEYS=$(gcloud iam service-accounts keys list \
    --iam-account=$SA \
    --project=$PROJECT_ID \
    --format="value(name.basename(),keyType,validAfterTime,validBeforeTime)")

  if [ -z "$KEYS" ]; then
    echo "$SA,No Keys,NA,-,-" >> $OUTPUT_FILE
  else
    echo "$KEYS" | while read KEY_ID KEY_TYPE CREATED EXPIRES
    do
      echo "$SA,$KEY_ID,$KEY_TYPE,$CREATED,$EXPIRES" >> $OUTPUT_FILE
    done
  fi
done

echo "Report saved to $OUTPUT_FILE"
