#!/usr/bin/env bash

set -xeuo pipefail

#This Script is for the kubernetes nginx ingress upgrade for prod clusters
export NAMESPACE="prod/dev"
export PROJECT_ID="***********************"
export NGINX_VERSION="******************"  


# Required tools kubectl, helm, yq, jq

# --- Function to check and install a tool ---
check_and_install() {
  local tool_name="$1"
  local install_command="$2"

  if ! command -v "$tool_name" &> /dev/null; then
    echo "Installing $tool_name..."
    eval "$install_command"
    if ! command -v "$tool_name" &> /dev/null; then
      echo "Error: Failed to install $tool_name."
      exit 1
    fi
    echo "$tool_name installed successfully."
  else
    echo "$tool_name is already installed."
  fi
}

# --- Check and install required tools ---

# Check for kubectl
check_and_install "kubectl" "curl -LO https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl && chmod +x kubectl && sudo mv kubectl /usr/local/bin/"

# Check for helm
check_and_install "helm" "curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 && chmod 700 get_helm.sh && ./get_helm.sh && rm get_helm.sh"

# Check for yq
check_and_install "yq" "sudo apt-get update && sudo apt-get install -y yq"

# Check for jq
check_and_install "jq" "sudo apt-get update && sudo apt-get install -y jq"


# --- setting the project id ---
gcloud config set project "${PROJECT_ID}"  --quiet


# --- adding and updating the helm repo ---
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

# --- filtering the clusters here based on regex we can filter the prod or dev, below is filtering only the dev clusters --- 
gcloud container clusters list \
  --filter='name:-prod-' \
  --format="value(name, location)" > prod_cluster.txt


if [[ ! -s "prod_cluster.txt" ]]; then
  echo "No clusters found."
  exit 0
fi

file="prod_cluster.txt"

read -rp "Press Enter to continue..." < /dev/tty

while read -r name location; do
    echo "Processing cluster: $name in region: $location"
    gcloud container clusters get-credentials "${name}" --region "${location}"

    if [[ $? -ne 0 ]]; then 
      echo "unable to get the cluster: $name crendentials" 
      continue 
    fi

    export ingress_namespace=$(helm list --filter "nginx*" --all-namespaces  --output json | jq '.[].namespace' | tr -d '"')
    export ingress_name=$(helm list --filter "nginx*" --all-namespaces  --output json | jq '.[].name' | tr -d '"')
    export ingress_current_version=$(helm list --filter "nginx*" --all-namespaces  --output json | jq '.[].chart' | tr -d '"')

    if [[ -z "$ingress_namespace" || -z "$ingress_name" ]]; then 
        echo "cluster ${name} is not using the nginx ingress"
        echo "nginx ingress patching not applied on cluster ${name} in the region ${location} " >> error.txt
        continue
    elif [[ ${ingress_namespace} != ${NAMESPACE} && ${ingress_current_version} != "ingress-nginx-${NGINX_VERSION}"  ]]; then 
        helm get values  "${ingress_name}" --namespace "${ingress_namespace}" > "${name}-values.yaml"
        export ip_ranges=$(kubectl get svc -n prod nginx-ingress-ingress-nginx-controller -o jsonpath='{.spec.loadBalancerSourceRanges}')
        yq -iy ".controller.service.loadBalancerSourceRanges = ${ip_ranges}" "${name}-values.yaml"
        read -rp "Press Enter to continue..." < /dev/tty
        sleep 2
        helm upgrade "${ingress_name}" ingress-nginx/ingress-nginx --namespace "${ingress_namespace}" -f "${name}-values.yaml" --version="${NGINX_VERSION}" 
    elif [[ ${ingress_current_version} != "ingress-nginx-${NGINX_VERSION}" ]]; then
        helm get values "${ingress_name}" --namespace "${ingress_namespace}" > "${name}-values.yaml"
        export ip_ranges=$(kubectl get svc -n prod nginx-ingress-ingress-nginx-controller -o jsonpath='{.spec.loadBalancerSourceRanges}')
        yq -iy ".controller.service.loadBalancerSourceRanges = ${ip_ranges}" "${name}-values.yaml"       
        read -rp "Press Enter to continue..." < /dev/tty
        sleep 2
        helm upgrade nginx-ingress ingress-nginx/ingress-nginx --namespace "${NAMESPACE}" -f "${name}-values.yaml" --version="${NGINX_VERSION}"
    else 
        echo "nginx ingress version for cluster ${name} is already updated to version ${ingress_current_version}...."
    fi

done < $file

echo "script completed"

 
 
