


# load env vars from spin-up
SPIN_UP_LOG=""
eval $(grep '^ATLAS\|^AZURE\|^DEMO' ${SPIN_UP_LOG})
# Fetch id's of any Azure resource


AZ_IDS=$(az resource list \
--tag "${DEMO_NAME}" --query '[].id' | \
jq -r -c '.[]')

for ID in ${AZ_IDS}
do
  echo "Found id='${ID}'"
done



# Delete MongoDB Atlas cluster
ATLAS_DELETE_CLUSTER_RAW_RSP=$(curl -s -u "${ATLAS_CREDS}" --digest \
--write-out "HTTPSTATUS:%{http_code}" \
-X DELETE \
"${ATLAS_URL}/groups/${ATLAS_GROUP_ID}/clusters/${ATLAS_CLUSTER_NAME}" \
)

HTTP_STATUS=$(echo ${ATLAS_DELETE_CLUSTER_RAW_RSP} | \
tr -d '\n' | sed -e 's/.*HTTPSTATUS://')

echo "Atlas delete cluster HTTP Status: ${HTTP_STATUS}"
ATLAS_DELETE_CLUSTER_RSP=$(echo "${ATLAS_DELETE_CLUSTER_RAW_RSP}" | \
sed -e 's/HTTPSTATUS:.*//g')
echo "Atlas delete cluster response: ${ATLAS_DELETE_CLUSTER_RSP}"

