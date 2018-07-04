#!/bin/bash
set -x



# load env vars from spin-up
SPIN_UP_LOG="./aem-on-azure-and-atlas.spin-up.log"
eval $(grep '^ATLAS\|^AZURE\|^DEMO' ${SPIN_UP_LOG})
# Fetch id's of any Azure resource

declare -p | grep '^ATLAS\|^AZURE\|^DEMO|^SPIN_DEMO'

# All Azure resource are associated with a single group.
# Deleting the group will delete everything.
az group delete --no-wait --yes --name ${DEMO_NAME}

# Delete MongoDB Atlas cluster
ATLAS_DELETE_CLUSTER_RSP=$(curl -s -u "${ATLAS_CREDS}" --digest \
-X DELETE \
"${ATLAS_URL}/groups/${ATLAS_GROUP_ID}/clusters/${ATLAS_CLUSTER_NAME}?envelope=true" \
)

HTTP_STATUS=$(echo ${ATLAS_DELETE_CLUSTER_RAW_RSP} | \
jq '.status')

echo "Atlas delete cluster HTTP Status: ${HTTP_STATUS}"
echo "Atlas delete cluster response: ${ATLAS_DELETE_CLUSTER_RSP}"

