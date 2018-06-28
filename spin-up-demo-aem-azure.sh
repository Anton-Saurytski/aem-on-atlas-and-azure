#!/bin/bash
set -x

DEMO_NAME="my-aem-demo"
echo "Spinning up AEM on Azure and Atlas demo"
echo "Azure Resource Group: ${DEMO_NAME}"

command -v az >/dev/null 2>&1 || \
{ echo >&2 "'az' command not found. Please install Azure CLI 2.0 first"; exit 1; }

AZ_USER=$(az account show --query 'user.name')
if [ -z "${AZ_USER}" ]; then
  echo "Unable to detect az account, use 'az login' first"
  exit 1
fi
echo "Detected az account user.name='${AZ_USER}'"

AEM_SOURCE_JAR="./AEM_6.4_Quickstart.jar"
AEM_LICENSE="./license.properties"
AEM_ADMIN_PWD="Ad0b3~AEM~0nAzureAndAtlasR0cks"

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

ATLAS_CONNSTR="mongodb://aem:aem@srv2-shard-00-00-n1oxl.mongodb.net:27017,srv2-shard-00-01-n1oxl.mongodb.net:27017,srv2-shard-00-02-n1oxl.mongodb.net:27017/test?ssl=true&replicaSet=srv2-shard-0&authSource=admin&retryWrites=true"

AEMPORT=4502
echo "Using port number ${AEMPORT} for aem author node."

az group create --resource-group ${DEMO_NAME} \
--location eastus

az resource list --output table

az vm create --name demo-aem-vm \
--resource-group ${DEMO_NAME} \
--public-ip-address demo-aem-public-ip \
--nsg demo-aem-nsg \
--image ubuntults \
--os-disk-size-gb 30 \
--size Standard_D2s_v3 \
--generate-ssh-keys \
--admin-username aem

az resource list --output table

az network nsg rule create --name demo-aem-allow-http-${AEMPORT} \
--resource-group ${DEMO_NAME} \
--nsg-name demo-aem-nsg \
--access Allow \
--direction Inbound \
--destination-port-range ${AEMPORT} \
--priority 102 \
--description "Allow inbound traffic from Internet to AEM"

az resource list --output table

az vm run-command invoke \
--resource-group ${DEMO_NAME} \
--name demo-aem-vm --command-id RunShellScript \
--scripts "sudo apt-get update && sudo apt-get install -y openjdk-8-jdk-headless"

AEMVMIP=$(az network public-ip list \
--resource-group ${DEMO_NAME} \
--output tsv \
--query '[0].ipAddress')
AEMJAR=aem-author-p${AEMPORT}.jar
scp ${AEM_SOURCE_JAR} aem@${AEMVMIP}:~/${AEMJAR}
scp ${AEM_LICENCE} aem@${AEMVMIP}:/license.properties

az vm run-command invoke \
--resource-group ${DEMO_NAME} \
--name demo-aem-vm --command-id RunShellScript \
--scripts "nohup java -XX:MaxPermSize=512M -mx4g \
-jar ${AEMJAR} -r author,crx3,crx3mongo \
-Dadmin.password=${AEM_ADMIN_PWD} \
-Doak.mongo.uri=\"${ATLAS_CONNSTR}\" </dev/null >aem.log 2>&1 &"



