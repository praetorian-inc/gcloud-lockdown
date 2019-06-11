#!/bin/bash
USAGE="./minimal_user.sh USER (USER is an existing gsuite email or gcloud service account)"
USER=$1

if [[ x${USER}x == 'xx' ]]; then
  echo $USAGE
fi

echo "add billing projectManager"
gcloud organizations add-iam-policy-binding --role roles/billing.projectManager --member user:$USER $ORGANIZATION_ID
echo "for now we also need billing.admin ... adding"
gcloud organizations add-iam-policy-binding --role roles/billing.admin --member user:$USER $ORGANIZATION_ID

