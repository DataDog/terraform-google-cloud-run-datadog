# Example: Deploying an Instrumented Python App to Cloud Run with Datadog

This example demonstrates how to use the `terraform-google-cloud-run-datadog` wrapper module to fully instrument your Python application with logs, metrics, and tracing using Datadog.

## Steps to Deploy
Create a [Datadog API Key](https://app.datadoghq.com/organization-settings/api-keys)
### 1. Set up Terraform variables

Create a `terraform.tfvars` file in this directory to configure all variables defined in `variables.tf`.  
You will define your Docker image path after building it in the next step.

### 2. Build and push the Docker image

Navigate to the `src/` subdirectory and build + push your application image to your Google Artifact Registry (or Container Registry) using the command line. If you don't have a registry, please go create one.

#### Authenticate to Google Cloud

```
gcloud auth login
```

Make sure you're logged in and have access to push to your registry.

#### Build the Docker image
```
docker buildx build \
  --platform linux/amd64 \
  -t $REGION-docker.pkg.dev/$PROJECT_ID/$REPO_NAME/$IMAGE_NAME:latest \
  .
```

#### Push image to the artifact registry
```
docker push $REGION-docker.pkg.dev/$PROJECT_ID/$REPO_NAME/$IMAGE_NAME:latest
```
#### Troubleshooting

If at any point you get authentication errors, rerun `gcloud auth login` and `gcloud auth configure-docker $REGION-docker.pkg.dev`

### 3. Configure the image in terraform.tfvars

Return to the example root (out of `/src`) and update the `image` variable in `terraform.tfvars` with the link you just pushed:
`image = <REGION>-docker.pkg.dev/<PROJECT_ID>/<REPO_NAME>/<IMAGE_NAME>:latest`

### 4. Deploy the instrumented app
Initialize and deploy:
```
terraform init
terraform plan
terrafrom apply
```
Your Python app is now fully instrumented with the Datadog sidecar agent. Tracing, logging, and metrics will be visible in Datadog Serverless Monitoring.
<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.5.0 |
| <a name="requirement_google"></a> [google](#requirement\_google) | >= 6.45.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_google"></a> [google](#provider\_google) | 6.45.0 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_datadog-cloud-run-v2-wrapper"></a> [datadog-cloud-run-v2-wrapper](#module\_datadog-cloud-run-v2-wrapper) | ../../ | n/a |

## Resources

| Name | Type |
|------|------|
| [google_cloud_run_service_iam_member.invoker](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/cloud_run_service_iam_member) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_datadog_api_key"></a> [datadog\_api\_key](#input\_datadog\_api\_key) | The api key for datadog | `string` | n/a | yes |
| <a name="input_image"></a> [image](#input\_image) | The image to deploy the service to | `string` | `"us-docker.pkg.dev/cloudrun/container/hello"` | no |
| <a name="input_location"></a> [location](#input\_location) | The region to deploy the service to | `string` | n/a | yes |
| <a name="input_name"></a> [name](#input\_name) | The name of the Cloud Run service | `string` | `"cloud-run-tf-python-test"` | no |
| <a name="input_project"></a> [project](#input\_project) | The project ID to deploy the service to | `string` | n/a | yes |
| <a name="input_region"></a> [region](#input\_region) | The region to deploy the service to | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_cloud_run_service_name"></a> [cloud\_run\_service\_name](#output\_cloud\_run\_service\_name) | Name of the Cloud Run service found on Datadog Serverless Monitoring. |
| <a name="output_service_containers"></a> [service\_containers](#output\_service\_containers) | List of containers in the Cloud Run service. |
| <a name="output_service_volumes"></a> [service\_volumes](#output\_service\_volumes) | List of volumes in the Cloud Run service. |
<!-- END_TF_DOCS -->