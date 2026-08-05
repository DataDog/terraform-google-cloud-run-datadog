#!/usr/bin/env bash
# Unless explicitly stated otherwise all files in this repository are licensed under the Apache-2.0 License.
# This product includes software developed at Datadog (https://www.datadoghq.com/) Copyright 2026 Datadog, Inc.

# Build and push e2e workload images from examples/*/src, then write e2e/.image-env
# with E2E_IMAGE_<RUNTIME>_<MODE> exports for the Go suite.
#
# Usage (from repo root or e2e/):
#   ./e2e/build_images.sh
#
# Required env:
#   GCP_PROJECT_ID
# Optional env:
#   GCP_REGION       (default: us-central1)
#   E2E_IMAGE_REPO   (default: e2e-workloads)
#   E2E_IMAGE_TAG    (default: git short SHA or timestamp)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
EXAMPLES_DIR="$REPO_ROOT/examples"
OUT_FILE="${E2E_IMAGE_ENV_FILE:-$SCRIPT_DIR/.image-env}"

PROJECT_ID="${GCP_PROJECT_ID:?GCP_PROJECT_ID is required}"
REGION="${GCP_REGION:-us-central1}"
REPO_NAME="${E2E_IMAGE_REPO:-e2e-workloads}"

if [ -n "${E2E_IMAGE_TAG:-}" ]; then
  TAG="$E2E_IMAGE_TAG"
elif command -v git >/dev/null 2>&1 && git -C "$REPO_ROOT" rev-parse --short HEAD >/dev/null 2>&1; then
  TAG="$(git -C "$REPO_ROOT" rev-parse --short HEAD)"
else
  TAG="$(date +%Y%m%d%H%M%S)"
fi

HOST="${REGION}-docker.pkg.dev"
BASE="${HOST}/${PROJECT_ID}/${REPO_NAME}"

echo "Building e2e images into ${BASE}:*:${TAG}"

if ! command -v gcloud >/dev/null 2>&1; then
  echo "Error: gcloud is required" >&2
  exit 1
fi
if ! command -v docker >/dev/null 2>&1; then
  echo "Error: docker is required" >&2
  exit 1
fi

gcloud config set project "${PROJECT_ID}" >/dev/null
gcloud auth configure-docker "${HOST}" --quiet

if ! gcloud artifacts repositories describe "${REPO_NAME}" --location="${REGION}" >/dev/null 2>&1; then
  echo "Creating Artifact Registry repository ${REPO_NAME} in ${REGION}"
  gcloud artifacts repositories create "${REPO_NAME}" \
    --repository-format=docker \
    --location="${REGION}" \
    --description="Ephemeral Cloud Run e2e workload images"
fi

: >"$OUT_FILE"
emit() {
  local key="$1"
  local value="$2"
  echo "export ${key}=${value}" >>"$OUT_FILE"
  echo "${key}=${value}"
}

# image_ref <runtime> <mode>  -> full image URI
image_ref() {
  echo "${BASE}/${1}-${2}:${TAG}"
}

build_docker_runtime() {
  local runtime="$1"
  local src="$EXAMPLES_DIR/${runtime}/src"
  if [ ! -f "$src/Dockerfile" ]; then
    echo "Error: missing Dockerfile at $src" >&2
    exit 1
  fi

  local sidecar_img
  sidecar_img="$(image_ref "$runtime" sidecar)"
  echo "====== Building ${runtime} sidecar (manual) ======"
  docker build --platform linux/amd64 --target manual -t "${sidecar_img}" "$src"
  docker push "${sidecar_img}"
  emit "E2E_IMAGE_$(echo "$runtime" | tr '[:lower:]-' '[:upper:]_')_SIDECAR" "${sidecar_img}"

  # Go has no SSI path in the module; still build an ssi-stage tag only when requested.
  if [ "${2:-}" = "ssi" ]; then
    local ssi_img
    ssi_img="$(image_ref "$runtime" ssi)"
    echo "====== Building ${runtime} ssi ======"
    docker build --platform linux/amd64 --target ssi -t "${ssi_img}" "$src"
    docker push "${ssi_img}"
    emit "E2E_IMAGE_$(echo "$runtime" | tr '[:lower:]-' '[:upper:]_')_SSI" "${ssi_img}"
  fi
}

# Dockerfile runtimes: sidecar (manual) for all; SSI stage where the module supports it.
build_docker_runtime go
build_docker_runtime node ssi
build_docker_runtime python ssi
build_docker_runtime ruby ssi
build_docker_runtime php ssi
build_docker_runtime dotnet ssi

# node-function: Cloud Buildpacks. One image serves sidecar + SSI (app gates manual tracer).
FN_SRC="$EXAMPLES_DIR/node-function/src"
FN_IMG="$(image_ref node-function sidecar)"
echo "====== Building node-function (pack) ======"
gcloud builds submit --pack \
  "image=${FN_IMG},env=GOOGLE_FUNCTION_TARGET=helloHttp" \
  --project "${PROJECT_ID}" \
  "$FN_SRC"
emit E2E_IMAGE_NODE_FUNCTION_SIDECAR "${FN_IMG}"
# Reuse the same pack image for SSI mode.
emit E2E_IMAGE_NODE_FUNCTION_SSI "${FN_IMG}"

echo
echo "Wrote ${OUT_FILE}"
echo "Source it before go test:"
echo "  set -a; source ${OUT_FILE}; set +a"
