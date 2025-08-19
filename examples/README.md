# Google Cloud Run Sidecar Instrumentation

Examples for instrumenting Google Cloud Run services with a Datadog sidecar
container.

## Available Languages

- [Python](./python)
- [Node.js](./node/)
- [Go](./go/)
- [Java](./java/)
- [.NET](./dotnet/)
- [Ruby](./ruby/)
- [PHP](./php/)

## Quick Deploy

Use the build and deploy script:

```bash
./build_and_deploy.sh <language>
```

### Examples

```shell
# Deploy Go application
./build_and_deploy.sh go

# Deploy Python application
./build_and_deploy.sh python

# Deploy Node.js application
./build_and_deploy.sh node
```

### Environment and Terraform Variables Required

Before running the script, ensure these environment variables are set:

```bash
export PROJECT_ID="your-gcp-project-id"
export GCP_PROJECT_NAME="your-cloud-run-service-name"
export DD_SERVICE="your-datadog-service-name"
export REPO_NAME="your-artifact-registry-repo"
export REGION="us-central1"  # Optional, defaults to us-central1
```

Terraform requires several parameters to be passed in: you can either wait for script to run and prompt on each variable needed, or ensure in the language's directory, that a `terraform.tfvars` file is created, with these following Terraform variables set:
```terraform
project="your-gcp-project-id"
region="us-central1" # same value as $REGION, whatever region you pushed your docker image too
name="your-cloud-run-service-name"
image="your-container-image-link" # follow the format in the `build_and_deploy.sh` script ("${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO_NAME}/${GCP_PROJECT_NAME}:latest")
datadog_api_key="your-datadog-api-key"
```