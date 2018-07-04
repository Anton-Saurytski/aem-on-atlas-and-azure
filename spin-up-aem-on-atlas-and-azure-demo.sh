#!/bin/bash
set -x
set -e

# For demonstration and testing purposes only!
# 
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# ~~~   ame-on-atlas-and-azure ~~~
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
# This script will provision a MongoDB Atlas cluster,
# Microsoft Azure linux virtual machine and then install 
# your Adobe AEM software. Once complete the script will run 
# a single AEM Author node. 
# 
# The environment variables below these comments must be set
# appropriately for things to work.
#
# Please refer to the README.me for a link to the blog post
# which describes this in more detail.
#
# This software is not supported by MongoDB, Inc. under any 
# of their commercial support subscriptions or otherwise. 
# Any usage of mtools is at your own risk. Bug reports, feature 
# requests and questions can be posted in the Issues section 
# on GitHub.
#
# ################################ #
# Update these variables - START
# ################################ #
# Read DEMO_NAME from command line OR default...
if [ -z "$1" ]; then
  DEMO_NAME_BASE="my-aem-demo"
  DEMO_NAME_UNIQUE=$(mktemp | cut -d'.' -f2 | cut -c 1-3)
  DEMO_NAME="${DEMO_NAME_BASE}-${DEMO_NAME_UNIQUE}"
else
  DEMO_NAME="$1"
fi

ATLAS_USER_EMAIL="jason.mimick"
ATLAS_APIKEY="c724264e-c03b-46ed-b513-ef37fb4a78fa"
ATLAS_PROJECT="panic1"
ATLAS_INSTANCE_SIZE="M30"
ATLAS_REPLICATION_FACTOR=3
ATLAS_DISK_SIZE_GB=100
ATLAS_CLUSTER_NAME="${DEMO_NAME}"

# Edit this to the desired Azure region.
AZURE_REGION="US_EAST"
AZURE_REGION_azcli="eastus"
AZURE_AEM_VM_NAME="${DEMO_NAME}-aem-vm"

AEM_SOURCE_JAR="./AEM_6.4_Quickstart.jar"
AEM_LICENSE="./license.properties"
AEM_ADMIN_PWD="Ad0b3~AEM~0nAzureAndAtlasR0cks"
AEM_PORT=4502

#CURL_VERBOSE="-vvv "
CURL_VERBOSE=""
# ################################ #
# Update these variables - END 
# ################################ #


echo "Spinning up AEM on Azure and Atlas demo"
echo "DEMO_NAME: ${DEMO_NAME}"
echo "Atlas Project: ${ATLAS_PROJECT}"
echo "Azure Resource Group: ${DEMO_NAME}"

command -v az >/dev/null 2>&1 || \
{ echo >&2 "'az' command not found. Please install Azure CLI 2.0 first"; exit 1; }


command -v jq >/dev/null 2>&1 || \
{ echo >&2 "'jq' command not found. Please install jq first (https://stedolan.github.io/jq/)"; exit 1; }

AZ_USER=$(az account show --query 'user.name')
if [ -z "${AZ_USER}" ]; then
  echo "Unable to detect az account, use 'az login' first"
  exit 1
fi
echo "Detected az account user.name='${AZ_USER}'"

ATLAS_CREDS="${ATLAS_USER_EMAIL}:${ATLAS_APIKEY}"
AEM_ADMIN_PWD_FILE="./admin.password.${DEMO_NAME}"
echo "admin.password = ${AEM_ADMIN_PWD}" > ${AEM_ADMIN_PWD_FILE}

AZURE_TAGS_DEMO_NAME=${DEMO_NAME}
AZURE_TAGS_ATLAS_CLUSTER_NAME=${ATLAS_CLUSTER_NAME}
AZURE_TAGS_ATLAS_PROJECT=${ATLAS_PROJECT}
DEMO_NAME_TAG="DEMO_NAME=${DEMO_NAME}"

if [ ! -f ${AEM_SOURCE_JAR} ]; then
  echo "Unable to find '${AEM_SOURCE_JAR}'"
  echo "Please download and reference your AEM jar file in this script."
  echo "Set the AEM_SOURCE_JAR variable."
  exit 1
fi
if [ ! -f ${AEM_LICENSE} ]; then
  echo "Unable to find '${AEM_LICENSE}'"
  echo "Be sure to reference a valid AEM license file."
  echo "Set the AEM_LICENSE variable."
  exit 1
fi

# You should be able to swap out this base url to 
# something else for Cloud or Ops Manager
ATLAS_URL="https://cloud.mongodb.com/api/atlas/v1.0"


# Fetch Atlas group id from group name
# FYI: Project ~= Group
ATLAS_GROUP_BYNAME_RSP=$(curl ${CURL_VERBOSE} -s \
-u "${ATLAS_CREDS}" \
--digest "${ATLAS_URL}/groups/byName/${ATLAS_PROJECT}")

ATLAS_GROUP_ID=$(echo ${ATLAS_GROUP_BYNAME_RSP} | jq -r '.id')

# Provision MongoDB Atlas cluster
ATLAS_CREATE_CLUSTER_REQUEST=$(cat << EOF
{
  "name" : "${ATLAS_CLUSTER_NAME}",
  "diskSizeGB" : ${ATLAS_DISK_SIZE_GB},
  "numShards" : 1,
  "providerSettings" : {
    "providerName" : "AZURE",
    "instanceSizeName" : "${ATLAS_INSTANCE_SIZE}",
    "regionName" : "${AZURE_REGION}"
  },
  "replicationFactor" : ${ATLAS_REPLICATION_FACTOR},
  "backupEnabled" : false
}
EOF
)

echo "ATLAS_CREATE_CLUSTER_REQUEST=${ATLAS_CREATE_CLUSTER_REQUEST}"

# TODO: refactor to use api ?envelope=true
ATLAS_CREATE_CLUSTER_RAW_RSP=$(curl ${CURL_VERBOSE} -s \
-u "${ATLAS_CREDS}" --digest \
-H "Content-Type: application/json" \
--write-out "HTTPSTATUS:%{http_code}" \
-X POST --data "${ATLAS_CREATE_CLUSTER_REQUEST}" \
"${ATLAS_URL}/groups/${ATLAS_GROUP_ID}/clusters"
)

HTTP_STATUS=$(echo ${ATLAS_CREATE_CLUSTER_RAW_RSP} | \
tr -d '\n' | sed -e 's/.*HTTPSTATUS://')

echo "Atlas create cluster HTTP Status: ${HTTP_STATUS}"
ATLAS_CREATE_CLUSTER_RSP=$(echo "${ATLAS_CREATE_CLUSTER_RAW_RSP}" | \
sed -e 's/HTTPSTATUS:.*//g')
echo "Atlas create cluster response: ${ATLAS_CREATE_CLUSTER_RSP}"

if [[ "${HTTP_STATUS}" != "201" ]]; then
  ERROR_CODE=$(echo ${ATLAS_CREATE_CLUSTER_RSP} | jq -r '.errorCode')
  if [[ "${ERROR_CODE}" != 'DUPLICATE_CLUSTER_NAME' ]]; then
    echo -e '*** ERROR ***\n'
    echo "An error was detected attempting to provision the MongoDB Atlas cluster."
    echo " Please review the raw HTTP response."
    echo ${ATLAS_CREATE_CLUSTER_RAW_RSP}
    exit 1
  else
    echo "Atlas cluster '${DEMO_NAME}' already exists, will use."
  fi
fi


xSTATUS="???"
while [[ "${xSTATUS}" != "IDLE" ]]; do
  ATLAS_CLUSTER_RSP=$(curl ${CURL_VERBOSE} \
  -s -u "${ATLAS_CREDS}" --digest \
  -H "Content-Type: application/json" \
  "${ATLAS_URL}/groups/${ATLAS_GROUP_ID}/clusters/${ATLAS_CLUSTER_NAME}")
  xSTATUS=$(echo ${ATLAS_CLUSTER_RSP} | jq -r '.stateName')
  echo "Current status for MongoDB Atlas cluster '${ATLAS_CLUSTER_NAME}' is: '${xSTATUS}'"
  sleep 5
  echo "Checking cluster status again..."
done




ATLAS_CONNSTR=$(echo ${ATLAS_CLUSTER_RSP} | jq -r '.mongoURIWithOptions')

#declare -p | grep ATLAS
#declare -p | grep AEM
#exit 1

#ATLAS_CONNSTR="mongodb://aem:aem@srv2-shard-00-00-n1oxl.mongodb.net:27017,srv2-shard-00-01-n1oxl.mongodb.net:27017,srv2-shard-00-02-n1oxl.mongodb.net:27017/test?ssl=true&replicaSet=srv2-shard-0&authSource=admin&retryWrites=true"

# Create MongoDB database user for AEM
# (just fetch HTTP status here???)
curl ${CURL_VERBOSE} -s \
-u "${ATLAS_CREDS}" --digest \
-H "Content-Type: application/json" \
-X POST "${ATLAS_URL}/groups/${ATLAS_GROUP_ID}/databaseUsers" \
--data @- <<EOF \

{
  "databaseName" : "admin",
  "roles" : [ {
    "databaseName" : "admin",
    "roleName" : "readWriteAnyDatabase"
  }, {
    "databaseName" : "admin",
    "roleName" : "dbAdminAnyDatabase"
  } ],
  "username" : "aem",
  "password" : "aem"
}
EOF

# Fetch all db users
curl ${CURL_VERBOSE} \
-s -u "${ATLAS_CREDS}" \
--digest "${ATLAS_URL}/groups/${ATLAS_GROUP_ID}/databaseUsers?pretty=true"

SPIN_DEMO_LOG="./aem-on-azure-and-atlas.spin-up.log"
if [[ -f ${SPIN_DEMO_LOG} ]]; then
  cp ${SPIN_DEMO_LOG} "./aem-on-azure-and-atlas.spin-up-$(date +"%F-%T").log"
fi

declare -p | grep '^ATLAS\|^AZURE\|^DEMO|^SPIN_DEMO' > ${SPIN_DEMO_LOG}

echo "Using port number ${AEM_PORT} for aem author node."

#Create Azure resource group for everything
az group create --resource-group ${DEMO_NAME} \
--location ${AZURE_REGION_azcli}

AZCLI_TAGS="--set tags.DEMO_NAME=${AZURE_TAGS_DEMO_NAME} \
--set tags.ATLAS_CLUSTER_NAME=${AZURE_TAGS_ATLAS_CLUSTER_NAME} \
--set tags.ATLAS_PROJECT=${AZURE_TAGS_ATLAS_PROJECT}"

echo "AZCLI_TAGS=${AZCLI_TAGS}"
#Tag resource group
az group update \
--resource-group ${DEMO_NAME} \
${AZCLI_TAGS}

az group list --output table --tag "${DEMO_NAME_TAG}"

#Provision VM for AEM
az vm create --name ${AZURE_AEM_VM_NAME} \
--resource-group ${DEMO_NAME} \
--public-ip-address demo-aem-public-ip \
--nsg demo-aem-nsg \
--image ubuntults \
--os-disk-size-gb 30 \
--size Standard_D2s_v3 \
--generate-ssh-keys \
--admin-username aem

#Tag VM (bug in azcli, multiple tags on create not parse correct)
az vm update --name ${AZURE_AEM_VM_NAME} \
--resource-group ${DEMO_NAME} \
${AZCLI_TAGS}

az resource list --output table --tag "${DEMO_NAME_TAG}"

AZ_NSG_NAME="${DEMO_NAME}-nsg"
AZ_NSG_RULE_NAME="${DEMO_NAME}-aem-allow-http-${AEM_PORT}"
az network nsg create --name ${AZ_NSG_NAME} \
--resource-group ${DEMO_NAME}

az network nsg update --name ${AZ_NSG_NAME} \
--resource-group ${DEMO_NAME} \
${AZCLI_TAGS}

az network nsg rule create --name ${AZ_NSG_RULE_NAME} \
--resource-group ${DEMO_NAME} \
--nsg-name ${AZ_NSG_NAME} \
--access Allow \
--direction Inbound \
--destination-port-range ${AEM_PORT} \
--source-address-prefixes '*' \
--priority 102 \
--description "Allow inbound traffic from Internet to AEM"

az network nsg rule update --name ${AZ_NSG_RULE_NAME} \
--nsg-name ${AZ_NSG_NAME} \
--resource-group ${DEMO_NAME} \
${AZCLI_TAGS}

az resource list --output table --tag "${DEMO_NAME_TAG}"

az vm run-command invoke \
--resource-group ${DEMO_NAME} \
--name demo-aem-vm --command-id RunShellScript \
--scripts "sudo apt-get update && sudo apt-get install -y openjdk-8-jdk-headless"

AEM_VM_IP=$(az network public-ip list \
--resource-group ${DEMO_NAME} \
--output tsv \
--query '[0].ipAddress')

echo "AEM_VM_IP=${AEM_VM_IP}"

AEMJAR=aem-author-p${AEM_PORT}.jar

echo "Uploading AEM assets to Azure VM '${AZURE_AEM_VM_NAME}"
yes | scp ${AEM_SOURCE_JAR} aem@${AEM_VM_IP}:~/${AEMJAR}
scp ${AEM_LICENCE} aem@${AEM_VM_IP}:~/license.properties
scp ${AEM_ADMIN_PWD_FILE} aem@${AEM_VM_IP}:~/admin.password

echo "Starting AEM Author node..."
az vm run-command invoke \
--resource-group ${DEMO_NAME} \
--name demo-aem-vm --command-id RunShellScript \
--scripts "nohup java -XX:MaxPermSize=512M -mx4g \
-jar ${AEMJAR} -r author,crx3,crx3mongo \
-Dadmin.password.file=~/admin.password \
-nointeractive \
-Doak.mongo.uri=\"${ATLAS_CONNSTR}\" </dev/null >aem.log 2>&1 &"

az resource list --output table \
--tag "${DEMO_NAME_TAG}" > ${SPIN_DEMO_LOG}

