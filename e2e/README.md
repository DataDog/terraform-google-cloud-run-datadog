# Cloud Run E2E Suite

End-to-end conformance tests for this module, implemented in Go + [Terratest].
They drive the full instrumentation lifecycle against a live, ephemeral Cloud
Run service and assert that the module both wires up Datadog correctly and that
telemetry actually flows.

This suite conforms to the shared serverless instrumentation e2e contract
([`serverless-ci/e2e/spec.md`][spec]). The module under test is the
instrumentation mechanism, so `terraform apply` is the APPLY step and
`terraform destroy` is the REMOVE step.

## Lifecycle

`TestCloudRunE2E` runs one service through:

1. **APPLY** — `terraform apply` of [`fixture/`](./fixture), which calls the
   module (`source = ../../`) to stand up an instrumented service. Because the
   module declaratively creates the service, provisioning the workload and
   instrumenting it happen in the same apply.
2. **Verify config** — `gcloud run services describe` confirms the
   `datadog-sidecar` (serverless-init) container, the shared volume + mounts,
   the wiring env vars (`DD_API_KEY`, `DD_SITE`, `DD_SERVICE`, `DD_HEALTH_PORT`,
   `DD_LOGS_INJECTION`, `DD_SERVERLESS_LOG_PATH`), and the identifying labels.
   Identifying values are asserted by **identity**, not mere existence.
3. **Trigger + verify telemetry** — HTTP GET the service URL, then poll the
   Datadog spans and logs APIs (15s × 20) until an event whose tags match this
   run's identity (`service`, `env`, `version`, `one_e2e_run_id`) appears.
4. **Idempotent re-apply** — `terraform plan -detailed-exitcode` must report no
   diff.
5. **REMOVE** — `terraform destroy`, then assert the service no longer exists
   (no residue: sidecar, volume, env vars, and labels all gone).

Teardown runs on every exit path, including failure.

## Resource hygiene

Every service is named `one-e2e-tf-cloud-run-<runid>` and labelled
`one_e2e_created=<unix-ts>` at creation. The cross-repo sweeper lists
`one-e2e-` resources and deletes any whose freshness label is stale or
unreadable, so these conventions are both identity and blast-radius guard.

## Pinned artifacts

| Artifact | Pinned to |
| -------- | --------- |
| Workload app | `self-monitoring-cloud-run-node-sidecar-prod` (prebuilt prod image, by digest) |
| Datadog sidecar | `gcr.io/datadoghq/serverless-init` (by digest) |

Pinning by digest means a red run blames this module, not upstream drift.
Override the workload image with `GCP_CLOUD_RUN_APP_IMAGE_E2E` and the sidecar
with `DD_SIDECAR_IMAGE_E2E`.

## Running locally

Prerequisites:

- **Terraform** ≥ 1.5 and **Go** (see [`go.mod`](./go.mod)).
- **GCP auth**: Application Default Credentials with access to the target
  project — `gcloud auth application-default login`. The principal needs Cloud
  Run admin and the ability to set an `allUsers` invoker IAM binding.
- **Datadog API + application keys** for the org the sidecar reports to.

Required environment:

| Var | Purpose |
| --- | ------- |
| `GCP_PROJECT_ID` | Project for the ephemeral service |
| `GCP_REGION` | Region (e.g. `us-central1`) |
| `DATADOG_API_KEY` (or `DD_API_KEY`) | Wired into the sidecar **and** used for telemetry queries |
| `DATADOG_APP_KEY` (or `DD_APP_KEY`) | Telemetry queries |
| `DD_SITE` | Datadog site (default `datadoghq.com`) |
| `GCP_CLOUD_RUN_APP_IMAGE_E2E` | Optional workload image override |
| `SKIP_CLOUD_RUN_TESTS=true` | Skip the suite |

The suite **skips** (does not fail) when it is disabled or when required
variables are absent.

```bash
cd e2e
export GCP_PROJECT_ID=datadog-serverless-gcp-dev
export GCP_REGION=us-central1
export DATADOG_API_KEY=... DATADOG_APP_KEY=...
go test -v -timeout 30m ./...
```

## CI

[`.github/workflows/e2e.yaml`](../.github/workflows/e2e.yaml) runs the suite on
PRs that touch the module or this directory. It authenticates to GCP via OIDC
workload-identity federation, and mints **short-lived Datadog credentials via
[dd-sts]** (GitHub OIDC → Datadog) rather than storing static API/App keys. The
job always runs (stable required check) and self-skips green via
`SKIP_CLOUD_RUN_TESTS` when no relevant files changed, or when the GCP OIDC
variables / dd-sts policy are not yet configured.

Repository configuration required (set by a maintainer), all **variables** (no
secrets):

- GCP OIDC: `GCP_WORKLOAD_IDENTITY_PROVIDER_E2E`, `GCP_SERVICE_ACCOUNT_E2E`,
  `GCP_PROJECT_ID_E2E`, `GCP_REGION_E2E`, `GCP_CLOUD_RUN_APP_IMAGE_E2E`.
- Datadog: `DD_SITE_E2E`. Telemetry auth is federated via [dd-sts]: the workflow's
  hardcoded `terraform-google-cloud-run-datadog-e2e` policy grants an API key for
  telemetry ingest plus an App key scoped to `apm_read` + `logs_read_data`.

[Terratest]: https://terratest.gruntwork.io/
[spec]: https://github.com/DataDog/serverless-ci/blob/main/e2e/spec.md
[dd-sts]: https://github.com/DataDog/dd-sts-action
