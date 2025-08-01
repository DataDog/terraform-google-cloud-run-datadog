# Example: Deploying an Instrumented Python App to Cloud Run with Datadog

This example demonstrates how to use the `terraform-google-cloud-run-datadog` wrapper module to fully instrument your Python application with logs, metrics, and tracing using Datadog.

## Steps to Deploy

### 1. Set up Terraform variables

Create a `terraform.tfvars` file in this directory to configure all variables defined in `variables.tf`.  
You will define your Docker image path after building it in the next step.

### 2. Build and push the Docker image

Navigate to the `src/` subdirectory and build + push your application image to your Google Artifact Registry (or Container Registry) using the command line.

#### Authenticate to Google Cloud

```
gcloud auth login
```

Make sure you're logged in and have access to push to your registry.

#### Create an Artifact Registry (if not created already)

```
# Set environment variables
PROJECT_ID=<your-project-id>
REGION="europe-west1"
REPO_NAME="cloud-run-source-deploy"
IMAGE_NAME="hello_world_image"

# Enable required API
gcloud services enable artifactregistry.googleapis.com

# Create the Docker repository
gcloud artifacts repositories create $REPO_NAME \
  --repository-format=docker \
  --location=$REGION \
  --description="Docker repo for Cloud Run apps"
```

#### Build the Docker image
```
docker buildx build \
  --platform linux/amd64 \
  -t $REGION-docker.pkg.dev/$PROJECT_ID/$REPO_NAME/$IMAGE_NAME:latest \
  .
```

#### Push image to the artiface Registry
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
Your Python app is now fully instrumented with the Datadog sidecar agent. Tracing, logging, and metrics metrics will be visible in Datadog Serverless Monitoring.