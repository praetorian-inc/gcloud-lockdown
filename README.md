# Gcloud Lockdown Demo Script

This repo demonstrates many best practices of a secure deployment on GCP including:
* VPC Service Controls
* Private GKE with concealed metadata service
* Automated per-tenant GCP Project creation connected to a shared services GCP Project
  to ensure a hard security boundary for multi-tenancy
* Complete Stackdriver Logging of all DATA_READ, DATA_WRITE and ADMIN_READ GCP Services activities
* Stackdriver Logging agent installed to bastion and GKE logging enabled
* Tests of malicious activity and detection capability

VPC Service Controls allow users to define a security perimeter around Google Cloud Platform resources such 
as Cloud Storage buckets, Bigtable instances, and BigQuery datasets to constrain data within a VPC and 
help mitigate data exfiltration risks.
This repo supports the blog describing this at ___.

In a nutshell, data exfiltration is easy via GCP Storage Buckets despite best practices to lock down networking with aggressive network egress policy. 
In order for cloud resources like VMs or Functions to access GCP Storage (other services like Cloud SQL or BigQuery also apply) the network proxy
must whitelist GCPs public dns names for the given services. This means an attacker can create a GCP Storage Bucket and exfiltrate to their own Bucket.
VPC Service Controls solve exactly this problem.

For a detailed presentation by the project manager see the [2019 Google Next video](https://youtu.be/rGCU6Ajo0QE).

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

If adding variables to .env files for contributing upstream, it is recommended that you add them to .env-sample
and then copy any data you want preserved (maybe just SOURCE_RANGES_IP_WHITELIST and FOLDER_RAND) from .env
and paste back into .env after clobbering.

```
> cp .env-sample .env
> <paste back your variables to .env>
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
Terraform is great for immutable infrastructure where all assets are controlled by Terraform, but it does not play well with mutations
or mixed managed/unmanaged resources.  Further, gcloud and Ansible lend themselves nicely to stepping through commands one at a time.
We hope to add Terraform modules, Deployment Manager templates and an Ansible playbooks for running the tests in time.  Contributions welcome!

### Terraform

https://www.terraform.io/docs/providers/google/r/dns_managed_zone.html
roles/dns.admin

### Ansible 
https://docs.ansible.com/ansible/latest/modules/list_of_cloud_modules.html

### Deployment Manager
https://cloud.google.com/deployment-manager/docs/best-practices/

#### Todo
https://github.com/jamesward/cloud-run-button
