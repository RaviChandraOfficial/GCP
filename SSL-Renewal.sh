#!/bin/bash
gcloud config set project <project-name>

# Output file
CLUSTER_FILE="clusters.txt"

# Namespace and secret info
SECRET_NAME="************"
NAMESPACE="prod/dev"
CERT_FILE="***********************.pem"
KEY_FILE="******************.key"

echo "Fetching GKE clusters..."
#gcloud container clusters list --filter="NOT name~'.*-prod-.*'" --format="value(name,location)" > "$CLUSTER_FILE"
gcloud container clusters list --filter="name~'.*-prod-.*'" --format="value(name,location)" > "$CLUSTER_FILE"

echo
echo "Cluster list saved to $CLUSTER_FILE:"
cat "$CLUSTER_FILE"

echo
read -p "Press Enter to continue once you've removed unwanted clusters from $CLUSTER_FILE..."

# Loop through each cluster
while IFS= read -r line; do
  CLUSTER_NAME=$(echo "$line" | awk '{print $1}')
  CLUSTER_LOCATION=$(echo "$line" | awk '{print $2}')
  
  echo "----------------------------------------"
  echo "Processing cluster: $CLUSTER_NAME in $CLUSTER_LOCATION"
  
  # Authenticate with the cluster
  gcloud container clusters get-credentials "$CLUSTER_NAME" --zone "$CLUSTER_LOCATION"

  # Check if secret exists
   if kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" >/dev/null 2>&1; then
     echo "Deleting existing secret $SECRET_NAME..."
     kubectl delete secret "$SECRET_NAME" -n "$NAMESPACE"
   fi

   echo "Creating new secret $SECRET_NAME..."
   kubectl create secret tls "$SECRET_NAME" \
     --cert="$CERT_FILE" \
    --key="$KEY_FILE" \
     -n "$NAMESPACE"

  echo "✅ Secret updated in $CLUSTER_NAME"
done < "$CLUSTER_FILE"

echo
echo "🎉 All selected clusters processed."
 
