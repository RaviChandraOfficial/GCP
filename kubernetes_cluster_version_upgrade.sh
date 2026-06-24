#!/usr/bin/env bash

set -eux -o pipefail

# Upgrade the GKE cluster control plane
# read -p "Enter your GKE Cluster Name: " name
# read -p "Enter your GKE Cluster Region: " region
# read -p "Enter your GKE Node Pool Name: " nodepool
 
export CLUSTER_NAME="*********************"
export CLUSTER_REGION="****************"
export NODEPOOL_NAME="*****************"
export TARGET_VERSION="*********************"
export PROJECT_ID="**************************"


# set the project id
gcloud config set project "$PROJECT_ID"
 
# authenticating to cluster
gcloud container clusters get-credentials "$CLUSTER_NAME" --region "$CLUSTER_REGION"
 
# checking the current version of cluster and upgrading cluster if not in the target version.
current_master_version=$(gcloud container clusters describe "$CLUSTER_NAME" --region "$CLUSTER_REGION" --format="value(currentMasterVersion)")
 
if [[ "${current_master_version}" != "1.33.5-gke.2072001" ]] then
  echo "Current Cluster Master Version: ${current_master_version} and Upgrading to target version: ${TARGET_VERSION}"
 
  gcloud container clusters upgrade ${CLUSTER_NAME} --master  --region=${CLUSTER_REGION}  --cluster-version 1.31.4-gke.1256000 -q
 
  gcloud container operations wait $(gcloud container operations list --filter="TYPE:UPGRADE_MASTER AND TARGET:${CLUSTER_NAME}" --format="value(name)" --limit=1) --region=${CLUSTER_REGION}
 
else
  echo "cluster is already in target version ${TARGET_VERSION}, skipping the master upgrade..."
fi
 
master_upgrade_status=$(gcloud container operations list --filter="TYPE:UPGRADE_MASTER AND TARGET:${CLUSTER_NAME}" --format="value(STATUS)" --limit=1)
 
node_pool_current_version=$(gcloud container clusters describe "$CLUSTER_NAME" --region "$CLUSTER_REGION" --format="value(currentNodeVersion)")
 
# Rollback if anything goes wrong if not than upgrading the NodePool...
if [[ "${master_upgrade_status}" != "DONE" ]] then
  echo "Some Issue Occured while upgrading the cluster, however we can't downgrade control plane version to another minor as mentioned in doc under limitation https://cloud.google.com/kubernetes-engine/docs/how-to/upgrading-a-cluster#downgrading-limitations, please check manually and raise case with GCP"
  echo "Status of cluster operation"
  gcloud container operation describe $(gcloud container operations list --filter="TYPE:UPGRADE_MASTER AND TARGET:${CLUSTER_NAME}" --format="value(name)" --limit=1)
 
  exit 1
else
  echo "Starting the NodePool upgrade..."
  if [[  "$node_pool_current_version" != "1.33.5-gke.1697000"  ]] then
    echo "Upgrading the nodepool $NODEPOOL_NAME ..."
    gcloud container clusters upgrade $CLUSTER_NAME --region=${CLUSTER_REGION} --node-pool=$NODEPOOL_NAME --cluster-version 1.31.4-gke.1256000 -q
    gcloud container operations wait $(gcloud container operations list --filter="TYPE:UPGRADE_NODES AND TARGET:${CLUSTER_NAME}" --format="value(name)" --limit=1) --region=${CLUSTER_REGION}
  else
    echo "The NodePool is already in the version $TARGET_VERSION"
  fi
fi
 
#Rolling back if anything goes wrong with the NodePool Upgrade..
nodepool_upgrade_status=$(gcloud container operations list --filter="TYPE:UPGRADE_NODES AND TARGET:${CLUSTER_NAME}" --format="value(STATUS)" --limit=1)
 
if [[ "$nodepool_upgrade_status" != "DONE" ]] then
  echo "Rolling back NodePool to previous version"
  gcloud container operations cancel $(gcloud container operations list --filter="TYPE:UPGRADE_NODES AND TARGET:${CLUSTER_NAME}" --format="value(name)" --limit=1)
  gcloud container node-pools rollback $NODEPOOL_NAME --cluster $CLUSTER_NAME
 
else
  echo "cluster is successfully upgraded..."
  exit 0
fi
 
