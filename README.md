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

## Quickstart

Modify `.env` as needed after copying it as per the code block below. It will be ignored by git.
The only required variable is replacing this default whitelisted IP with your vpn or home router IP.

* SOURCE_RANGES_IP_WHITELIST=1.1.1.1/32

```
git clone https://github.com/praetorian-code/vpc-service-controls.git
cd vpc-service-controls
cp .env-sample .env
./create_service_control_project.sh
```


## Troubleshooting

Uncomment the `set -x` line at the top.
This script is not entirely idempotent so you may need to comment out lines on second runs or reset the $RAND, $FOLDER_RAND and $SHARED_RAND variables.
The most likely culprit for problems is not having the correct permissions. Find the line that fails and on the commandline run the following:

```
source .env
<paste and run the failing command>
```

## Design

Why bash scripts? We thought it is most instructive to run commands in an interactive way by pasting individual `gcloud` commands.

Ansible was considered, but it doesn't have support for many of the project/organization commands so it would be a lot of shell commands.

We hope to add Terraform modules, Deployment Manager templates and an Ansible playbooks for running the tests in time.  Contributions welcome!

### Terraform

https://www.terraform.io/docs/providers/google/r/dns_managed_zone.html
roles/dns.admin

### Ansible 
https://docs.ansible.com/ansible/latest/modules/list_of_cloud_modules.html

### Deployment Manager
https://cloud.google.com/deployment-manager/docs/best-practices/
