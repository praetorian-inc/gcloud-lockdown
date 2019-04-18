#!/bin/bash

set -x

abort()
{
    echo >&2 '
***************
*** ABORTED ***
***************
'
    echo "An error occurred. Exiting..." >&2
    exit 1
}

trap 'abort' 0

set -e

function set_var(){
    varname=$1
    varvalue=$2
    if [[ "$OSTYPE" == "linux-gnu" ]]; then
        sed -i "s/^${varname}=$/${varname}=${varvalue}/" .env
        # ...
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "s/^${varname}=$/${varname}=${varvalue}/" .env
            # Mac OSX
    else 
        echo "os $OSTYPE not supported"
        abort
        # POSIX compatibility layer and Linux environment emulation for Windows
    fi
}

source .env

echo "get organization"
ORGANIZATION_ID=`gcloud organizations list --format json | jq '.[0].name' | sed 's/\"//g'`
if [ x${ORGANIZATION_ID} != xx ]; then
    ORGANIZATION_ID=`echo $ORGANIZATION_ID | cut -d "/" -f 2`
    set_var ORGANIZATION_ID $ORGANIZATION_ID
   echo "using ORGANIZATION_ID $ORGANIZATION_ID"
else
   echo "gcloud organizations list failed. Check your user is admin for an organization."
   abort
fi

if [ x${FOLDER_RAND}x == xx ]; then 
    echo "FOLDER_RAND not set, creating random folder suffix"
    FOLDER_RAND=${RANDOM}
    set_var "FOLDER_RAND" ${FOLDER_RAND}
else
    echo "Using folder random suffix $FOLDER_RAND"
fi

echo "checking for folder $FOLDER_ID"
FOLDER_NUMBER=`gcloud resource-manager folders list --organization $ORGANIZATION_ID | grep $FOLDER_ID | awk '{print $3}' || echo ""`
if [ x${FOLDER_NUMBER}x != xx ]; then
    echo "found folder $FOLDER_NUMBER"
else 
    echo "create a folder $FOLDER_ID"
    gcloud alpha resource-manager folders create --display-name $FOLDER_ID --organization $ORGANIZATION_ID
    FOLDER_NUMBER=`gcloud resource-manager folders list --organization $ORGANIZATION_ID | grep "${FOLDER_ID} " | awk '{print $3}' || echo ""`
fi
set_var FOLDER_NUMBER $FOLDER_NUMBER 

if [ x${RAND}x == xx ]; then 
    echo "New run, creating random project suffix"
    RAND=${RANDOM}
    set_var "RAND" ${RAND}
else
    echo "Using random suffix $RAND"
fi

POLICY_ID=`gcloud access-context-manager policies list --organization $ORGANIZATION_ID --project vpc-service-control | tail -n +2 | awk '{print $1}' || echo ""`
if [ x${POLICY_ID}x == xx ]; then
    echo "create an organization policy as a container for the service perimeter"
    echo "It seems that we can only create one policy per organization"
    echo "There is something strange because gcloud requires a --project variable, but "
    gcloud access-context-manager policies create  --organization $ORGANIZATION_ID --title $POLICY_TITLE --project=${SHARED_PROJECT_ID}
else
    echo "found policy id $POLICY_ID"
fi
set_var POLICY_ID $POLICY_ID

if [ x${SHARED_RAND}x == xx ]; then 
    echo "No SHARED_RAND variable found, creating random shared project suffix"
    SHARED_RAND=${RANDOM}
    set_var SHARED_RAND $SHARED_RAND
else
    echo "Using random suffix $SHARED_RAND"
fi

if [ x${RAND}x == xx ]; then
    echo "No RAND variable found, creating random project suffix"
    RAND=${RANDOM}
    set_var RAND $RAND
else
    echo "Using random suffix $RAND"
fi

# source again to get RAND and SHARED_RAND templating
source .env

if [ x${BILLING_ACCOUNT}x == xx]; then
    BILLING_ACCOUNT=`gcloud alpha billing accounts list | tail -n +2 | awk '{print $1}'`
    set_var BILLING_ACCOUNT $BILLING_ACCOUNT
fi

if [ x${PROJECT_NUMBER}x == xx ]; then
    echo "CREATE THE $PROJECT_NAME PROJECT under folder number $FOLDER_NUMBER"
    projects_json=`gcloud projects create $PROJECT_NAME --folder $FOLDER_NUMBER --labels $PROJECT_LABELS --format json`
    PROJECT_NUMBER=`echo $projects_json | jq '.projectNunber' | sed 's/\"//g'`
    set_var PROJECT_NUMBER $PROJECT_NUMBER
    gcloud alpha billing projects link $PROJECT_ID --billing-account $BILLING_ACCOUNT
fi

if [ x${SHARED_PROJECT_NUMBER}x == xx ]; then
    echo "CREATE THE $SHARED_PROJECT_NAME Shared Project under folder number $FOLDER_NUMBER"
    projects_json=`gcloud projects create $SHARED_PROJECT_NAME --folder $FOLDER_NUMBER --labels $SHARED_PROJECT_LABELS --format json`
    SHARED_PROJECT_NUMBER=`echo $projects_json | jq '.projectNumber' | sed 's/\"//g'`
    if [ ${SHARED_PROJECT_NUMBER} != null ]; then
        set_var SHARED_PROJECT_NUMBER $SHARED_PROJECT_NUMBER
    fi
    gcloud alpha billing projects link $SHARED_PROJECT_ID --billing-account $BILLING_ACCOUNT
fi

bq_tables=`bq ls --project_id $SHARED_PROJECT_ID`
if [ x${bq_tables}x == xx ]; then
    echo "Using BigQuery dataset $bq_tables for logging sink"
else
    echo "Create a bigquery table for Stackdriver Logging for all projects in shared"
    bq --location=$REGION mk --dataset --default_table_expiration [INTEGER] --default_partition_expiration [INTEGER2] --description [DESCRIPTION] [PROJECT_ID]:[DATASET]
fi

stackdriver_bucket=`gsutil ls -p $SHARED_PROJECT_ID -l $REGION | grep $STACKDRIVER_BUCKET || echo ""`
if [ x${stackdriver_bucket}x == xx ]; then
    echo "Create a Storage Bucket for Stackdriver Logging for all projects in shared"    
    gsutil mb -p $SHARED_PROJECT_ID -l $REGION gs://$STACKDRIVER_BUCKET
fi

echo "For each tenant project, we will create a bucket for logging and a bucket for data in the shared project"
echo "We will create a Cloud Function to handle authorizing a new tenant to its buckets in the shared project"

gcloud services enable vpcaccess.googleapis.com --project $SHARED_PROJECT_ID

gcloud beta compute networks vpc-access connectors create $SHARED_FUNCTION_CONNECTOR_NAME \
--network $SHARED_VPC_NAME \
--region $REGION \
--range 10.8.0.0/28

function enable_full_logging() {
  PROJECT_ID = $1

read -r -d '' LOGGING_BLOCK <<-'EOF'
auditConfigs:
 - service: allServices
   auditLogConfigs:
    - logType: ADMIN_READ
    - logType: DATA_READ
    - logType: DATA_WRITE
EOF
 echo "${LOGGING_BLOCK}" >> /tmp/iam-policy.json

}

###########################################################
# All variables should be set now.
# Non idempotent from here. Have to comment out on restart.
###########################################################

function configure_project() {
  PROJECT_ID=$1
  PROJECT_NUMBER=$2
  VPC_NAME=$3
  ZONE_NAME=$4
  BUCKET=$5
  PERIMETER_NAME=$6
  PERIMETER_TITLE=$7

  echo "enabling servies - maximum batch size is 20"
  gcloud services enable `cat services1.txt` --project $PROJECT_ID
  gcloud services enable `cat services2.txt` --project $PROJECT_ID
  
  # echo "create a service account and attach a minimal policy"
  # gcloud iam service-accounts create $SERVICE_ACCOUNT \
  #     --display-name ${SERVICE_ACCOUNT_DESCRIPTION}
  
  # echo "grant the service_account policy admin permissions"
  # gcloud organizations add-iam-policy-binding ORGANIZATION_ID \
  #   --member="serviceAccount:${SERVICE_ACCOUNT}@${PROJECT_NUMBER}.iam.gserviceaccount.com" \
  #   --role="roles/accesscontextmanager.policyAdmin"

     

  echo "create $PROJECT_ID bucket now because you cannot after service perimeter is up"
  gsutil mb -p $PROJECT_ID -l $REGION gs://$BUCKET
  
  echo "create a log sink to bigquery in shared project"
  gcloud beta logging sinks create $BIGQUERY_SHARED_DATASET \
      bigquery.googleapis.com/projects/my-project/datasets/$BIGQUERY_SHARED_DATASET

  echo "create a security perimeter for the tenant project"
  echo "GOTCHA - perimeter name cannot have a dash '-'"
  gcloud access-context-manager perimeters create $PERIMETER_NAME \
   --policy=${POLICY_ID} --title=$PERIMETER_TITLE \
   --resources=projects/${PROJECT_NUMBER}   --restricted-services=$SERVICES \
   --project=${PROJECT_ID}
  
  echo "get the compute service account created for the project"
  COMPUTE_SERVICE_ACCOUNT=`gcloud projects get-iam-policy $PROJECT_ID | grep 'developer.gserviceaccount.com' | cut -d':' -f2`
  # gcloud projects add-iam-policy-binding  \
  # --member serviceAccount:$COMPUTE_SERVICE_ACCOUNT \
  # --role roles/storage.admin $PROJECT_ID
  
  gcloud compute networks create ${VPC_NAME} --description=SERVICE_CONTROL_VPC --project $PROJECT_ID
  
  gcloud beta compute firewall-rules create deny-all \
  --project=$PROJECT_ID \
  --network $VPC_NAME \
  --direction ingress \
  --action deny \
  --rules all \
  --enable-logging 
  
  gcloud beta compute firewall-rules create allow-whitelist --network $VPC_NAME \
  --project=$PROJECT_ID \
  --direction ingress \
  --action allow \
  --rules tcp:443,icmp,tcp:22 \
  --source-ranges $SOURCE_RANGES_IP_WHITELIST \
  --target-tags bastion \
  --enable-logging 

  gcloud beta dns managed-zones create $ZONE_NAME \
    --visibility=private \
    --networks=https://www.googleapis.com/compute/v1/projects/$PROJECT_ID/global/networks/$VPC_NAME \
    --description="${ZONE_DESCRIPTION}" \
    --dns-name=googleapis.com \
    --project $PROJECT_ID
  
  gcloud dns record-sets transaction start --zone=$ZONE_NAME --project=$PROJECT_ID
  gcloud dns record-sets transaction add --name=*.googleapis.com. \
   --type=CNAME restricted.googleapis.com. \
   --zone=$ZONE_NAME \
   --ttl=300 --project=$PROJECT_ID
  gcloud dns record-sets transaction execute --zone=$ZONE_NAME --project=$PROJECT_ID

  echo "create bastion host for tenant"
  echo "default scopes are storage.readonly. must over-ride them."
  gcloud compute instances create bastion-$PROJECT_ID \
  --project $PROJECT_ID \
  --machine-type f1-micro \
  --boot-disk-auto-delete \
  --boot-disk-size 10GB \
  --network $VPC_NAME \
  --image-family debian-9 \
  --image-project debian-cloud \
  --tags bastion \
  --zone $ZONE \
  --scopes $SCOPES 

}

configure_project $SHARED_PROJECT_ID $SHARED_PROJECT_NUMBER $SHARED_VPC_NAME \
  $SHARED_ZONE_NAME $SHARED_BUCKET $SHARED_PERIMETER_NAME $SHARED_PERIMETER_TITLE \
  $SHARED_SOURCE_RANGES_IP_WHITELIST

trap : 0

echo >&2 '
************
*** DONE *** 
************
'





# echo "CREATE THE SHARED PROJECT"
# echo "note that sec_level is high because shared resources have a higher attack value"
# gcloud projects create $SHARED_PROJECT_ID --folder $FOLDER_ID --labels $SHARED_PROJECT_LABELS
# gcloud alpha billing projects link $SHARED_PROJECT_ID --billing-account $BILLING_ACCOUNT
# gsutil mb -p $SHARED_PROJECT_ID  gs://test-shared-bucket-created-by-bastion 
# gcloud compute networks create ${VPC_NAME} --description=TENANT_PROJECT_VPC --project $PROJECT_ID


# gcloud access-context-manager perimeters   create ${SHARED_PROJECT_PERIMETER} --policy=${POLICY_ID} --title=$SHARED_POLICY_TITLE   --resources=projects/${SHARED_PROJECT_NUMBER}   --restricted-services=$SERVICES --project=${SHARED_PROJECT_ID}

# echo "create bridge resources"
# echo "bridge name cannot start with numbers. try with numerical prefix"
# gcloud access-context-manager perimeters create bridge   --title="${PROJECT_ID}PerimeterBridge" --perimeter-type=bridge   --resources=projects/${PROJECT_NUMBER},projects/${SHARED_PROJECT_NUMBER} --policy=${POLICY_ID} --project=${PROJECT_ID}

# gcloud projects add-iam-policy-binding  \
# --member serviceAccount:service-568160633113@compute-system.iam.gserviceaccount.com \
# --role roles/storage.admin $SHARED_PROJECT_ID

# gcloud beta compute firewall-rules create deny-all \
# --project=$SHARED_PROJECT_ID \
# --network $SHARED_VPC_NAME \
# --direction ingress \
# --action deny \
# --rules all \
# --enable-logging 

# gcloud beta compute firewall-rules create allow-whitelist --network $SHARED_VPC_NAME \
# --project=$SHARED_PROJECT_ID \
# --direction ingress \
# --action allow \
# --rules tcp:443,icmp,tcp:22 \
# --source-ranges 35.196.215.192/32,35.188.30.0/32 \
# --target-tags bastion \
# --enable-logging 


# gcloud compute networks create ${SHARED_VPC_NAME} --description=SHARED_PROJECT_VPC --project $SHARED_PROJECT_ID 

# echo "create bastion host for shared project"
# echo "default scopes are storage.readonly. must over-ride them."
# gcloud compute instances create bastion-$PROJECT_ID \
# --project $PROJECT_ID \
# --machine-type f1-micro \
# --boot-disk-auto-delete \
# --boot-disk-size 10GB \
# --network $VPC_NAME \
# --image-family debian-9 \
# --image-project debian-cloud \
# --tags bastion \
# --zone us-central1-a \
# --scopes $SHARED_SCOPES
# --service-account 



# gcloud compute ssh --zone us-central1-a bastion-shared-gcp-services --project $SHARED_PROJECT_ID

# gsutil mb -p shared-gcp-services -l us-central1 gs://test-shared-bucket-created-by-bastion-SHARED_RAND

# Sec210 validator
# Inventory
# Access troubleshooter, IAM recommender
# APN Partner early access

# Bit.ly/notebooks-best-practices
# Bit.ly/notebooks-ci
# Bit.ly/nova-extension

# AI Platform Notebooks

# gsutil iam ch [MEMBER_TYPE]:[MEMBER_NAME]:[ROLE] gs://[BUCKET_NAME]

# https://www.terraform.io/docs/providers/google/r/dns_managed_zone.html
# roles/dns.admin


