# Cloud Run E2E tests

Live instrumentation lifecycle against ephemeral Cloud Run services for every
runtime under [`examples/`](../examples). Each mode is built from its own example:
sidecar images come from `examples/<runtime>`, which ships the tracer in the image,
and Single-Language SSI images from `examples/<runtime>-ssi`, which ships no tracer
and lets the module inject one. SSI covers `node`, `python`, `ruby`, `php`,
`dotnet`, and `node-function`; Go is sidecar-only.

## Run locally


You need Go, Terraform, Docker, `gcloud`, Google Application Default Credentials
with permission to manage Cloud Run / Artifact Registry / Cloud Build and grant
the Cloud Run Invoker role, and a Datadog account that can create API and
application keys. 
Ensure GCP_PROJECT_ID, GCP_REGION, and DD_SITE are set in the environment.

```bash
gcloud auth login
gcloud auth application-default login
gcloud config set project "$GCP_PROJECT_ID"
gcloud auth configure-docker "${GCP_REGION}-docker.pkg.dev"

# 1) Build + push workload images from the example dirs (writes e2e/.image-env)
./e2e/build_images.sh

# 2) Run the suite
cd e2e
set -a; source .image-env; set +a
dd-auth --domain "$DD_SITE" -- go test -count=1 -v -timeout 120m ./...
```

Run a single live scenario (after sourcing `.image-env`):

```bash
go test -count=1 -v -timeout 30m -run 'TestCloudRunE2E/node_ssi' ./...
go test -count=1 -v -timeout 30m -run 'TestCloudRunE2E/python_sidecar' ./...
```

## What the tests check

Each subtest of **TestCloudRunE2E**:

1. Applies the module via `e2e/fixture` (unique Terraform dir per parallel subtest)
2. Verifies sidecar / shared volume / env / labels (and SSI tracer wiring when enabled)
3. Triggers the service URL and waits for matching Datadog spans + logs
4. Asserts `terraform plan` is a no-op
5. Destroys and asserts the service is gone

SSI scenarios additionally assert:

- `datadog-tracer` sidecar + `datadog-tracer` volume
- language injection env (`NODE_OPTIONS`, `PYTHONPATH`, …) and app `dependsOn` the tracer sidecar
- `_dd.injection.mode:serverless-single-lang` leading the app container's `DD_TAGS`, with the
  agent sidecar's `DD_TAGS` left as configured

Workload images are built by [`build_images.sh`](./build_images.sh) into
`$GCP_REGION-docker.pkg.dev/$GCP_PROJECT_ID/e2e-workloads/<runtime>-<mode>:<tag>`.
Environment variables look like `E2E_IMAGE_NODE_SSI`, `E2E_IMAGE_GO_SIDECAR`, …

## CI

[The E2E workflow](../.github/workflows/e2e.yaml) runs when Terraform, e2e, or
examples files change. It builds images, then runs the matrix with short-lived
Google Cloud and Datadog credentials.
