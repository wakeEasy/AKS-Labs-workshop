### 1) Deploy Azure resources using Bicep


## You must ensure the region where you choose to deploy supports availability zones to demonstrate the concepts in the some of the workshops.
## You can list the regions that support availability zones using the following command:
az account list-locations --query "[?metadata.regionType=='Physical' && metadata.supportsAvailabilityZones==true].{Region:name}" -o table

export RG_NAME="myResourceGroup"
export LOCATION="eastus"
export USER_ID="$(az ad signed-in-user show --query id -o tsv)"
export DEPLOY_NAME="labdemo"

curl  -o main.bicep https://raw.githubusercontent.com/azure-samples/aks-labs/refs/heads/main/docs/storage/assets/main.bicep

az deployment group create \
--name ${DEPLOY_NAME} \
--resource-group $RG_NAME \
--template-file 1_part.bicep \
--parameters userObjectId=${USER_ID} \
--no-wait

### 2) Creating an AKS Cluster

## Find the VMs SKU size that works:
# az vm list-skus --location eastus --size Standard_B --all --output table

## Before creating the AKS cluster you need to decide on the Kubernetes version to use.
## It is recommended to use the latest version of Kubernetes available in the region you are deploying to.
## You can find the latest version of Kubernetes available in your region by running the following command:
#export K8S_VERSION=$(az aks get-versions -l ${LOCATION} --query "reverse(sort_by(values[?isDefault==true].{version: version}, &version)) | [0] " -o tsv)

export K8S_VERSION="1.31"
export AKS_NAME="oz-lab-aks"

az aks create \
--resource-group ${RG_NAME} \
--name ${AKS_NAME} \
--location ${LOCATION} \
--tier standard \
--kubernetes-version ${K8S_VERSION} \
--os-sku AzureLinux \
--nodepool-name systempool \
--node-count 2 \
--node-vm-size "Standard_B2pls_v2" \
--zones 1 2 3 \
--load-balancer-sku standard \
--network-plugin azure \
--network-plugin-mode overlay \
--network-dataplane cilium \
--network-policy cilium \
--enable-managed-identity \
--enable-acns \
--generate-ssh-keys


### 3) Adding a User Node Pool
az aks nodepool add \
--resource-group ${RG_NAME} \
--cluster-name ${AKS_NAME} \
--mode User \
--name userpool \
--node-count 1 \
--node-vm-size Standard D2as_v4 \
--zones 1 2 3


### 4) Tainting the System Node Pool
az aks nodepool update \
--resource-group ${RG_NAME} \
--cluster-name ${AKS_NAME} \
--name systempool \
--node-taints CriticalAddonsOnly=true:NoSchedule

### Export outputs to Environment variables:
while IFS= read -r line; \
do echo "exporting $line"; \
export $line=$(az deployment group show -g ${RG_NAME} -n ${DEPLOY_NAME} --query "properties.outputs.${line}.value" -o tsv); \
done < <(az deployment group show -g $RG_NAME -n ${DEPLOY_NAME} --query "keys(properties.outputs)" -o tsv)


### Enable the monitoring addon which will enable logging to the Azure Log Analytics workspace from the AKS cluster:
az aks enable-addons \
--resource-group ${RG_NAME} \
--name ${AKS_NAME} \
--addon monitoring \
--workspace-resource-id ${logs_id} \
--no-wait

### 5) Deploying the AKS Store Demo Application

kubectl create namespace pets

kubectl apply -f https://raw.githubusercontent.com/Azure-Samples/aks-store-demo/refs/heads/main/aks-store-quickstart.yaml -n pets



