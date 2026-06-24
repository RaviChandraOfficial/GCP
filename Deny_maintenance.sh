#!/bin/bash

# Define projects
PROD_PROJECT="***********************"
NONPROD_PROJECT="**********************"
FILE="instances.txt"

# Choose project
echo "Select the project you want to use:"
echo "1) Production  - $PROD_PROJECT"
echo "2) Non-Prod    - $NONPROD_PROJECT"
read -p "Enter your choice (1 or 2): " CHOICE

case $CHOICE in
  1)
    PROJECT_ID=$PROD_PROJECT
    ;;
  2)
    PROJECT_ID=$NONPROD_PROJECT
    ;;
  *)
    echo "❌ Invalid choice. Exiting."
    exit 1
    ;;
esac

echo ""
echo "🔧 Setting gcloud project to: $PROJECT_ID ..."
gcloud config set project "$PROJECT_ID" >/dev/null

# Ask for start date
read -p "Enter Start Date (YYYY-MM-DD): " START_DATE

# Validate start date
if ! date -d "$START_DATE" >/dev/null 2>&1; then
  echo "❌ Invalid date format. Use YYYY-MM-DD."
  exit 1
fi

# Fetch Cloud SQL primary instances (exclude replicas)
echo ""
echo "🔍 Fetching Cloud SQL instances (excluding replicas) ..."
INSTANCES=$(gcloud sql instances list --project="$PROJECT_ID" \
  --filter="-name:replica" \
  --format="value(name)")

if [ -z "$INSTANCES" ]; then
  echo "❌ No primary Cloud SQL instances found in project '$PROJECT_ID'."
  exit 1
fi

# Write instances to file
echo "# Remove any unneeded instances below before proceeding" > "$FILE"
echo "# ---------------------------------------------" >> "$FILE"
echo "$INSTANCES" >> "$FILE"

echo ""
echo "✅ Instances written to: $FILE"
echo "📝 Please review the file and remove any unwanted instances manually."
read -p "Press Enter once you’ve finished editing the file..."

# Read final instance list (skip comments/empty lines)
FINAL_INSTANCES=$(grep -v '^#' "$FILE" | grep -v '^$')

if [ -z "$FINAL_INSTANCES" ]; then
  echo "❌ No valid instances left in $FILE. Exiting."
  exit 1
fi

# Show final confirmation list
echo ""
echo "📋 Final instance list to be processed:"
echo "-------------------------------------"
echo "$FINAL_INSTANCES"
echo "-------------------------------------"
read -p "Please review the above list. Press Enter to continue or Ctrl+C to cancel..."

# Calculate end date = start date + 90 days
END_DATE=$(date -d "$START_DATE +90 days" +%Y-%m-%d)

echo ""
echo "📅 Maintenance deny period: $START_DATE → $END_DATE"
echo ""

# Patch each instance
for INSTANCE in $FINAL_INSTANCES; do
  echo "🚀 Updating maintenance deny period for instance: $INSTANCE"
  gcloud sql instances patch "$INSTANCE" \
    --project="$PROJECT_ID" \
    --deny-maintenance-period-start-date="$START_DATE" \
    --deny-maintenance-period-end-date="$END_DATE" \
    --deny-maintenance-period-time=00:00:00
  echo ""
done

echo "✅ All selected instances processed successfully." 
