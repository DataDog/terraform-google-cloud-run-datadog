# Cloud Run E2E tests

## Run locally

You need Go, Terraform, Google Application Default Credentials with permission to manage Cloud Run and grant the Cloud Run Invoker role, and a Datadog account that can create API and application keys.

```bash
gcloud auth application-default login

cd e2e
dd-auth --domain ddserverless.datadoghq.com -- go test -count=1 -v -timeout 30m ./...
```

The test defaults to `datadog-serverless-gcp-dev` in `us-central1`. Set `GCP_PROJECT_ID` or `GCP_REGION` to override either value.

## What the test checks

The test deploys a temporary Cloud Run service, verifies its Datadog configuration and telemetry, confirms Terraform has no further changes, then deletes the service.

## CI

[The E2E workflow](../.github/workflows/e2e.yaml) runs when Terraform or E2E files change. It uses short-lived Google Cloud and Datadog credentials.
