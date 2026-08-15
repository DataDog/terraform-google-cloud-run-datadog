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

# Each mode has its own example directory: examples/<runtime> ships the tracer in the
# image, examples/<runtime>-ssi ships no tracer and lets the module inject one.
example_dir() {
  case "$2" in
  ssi) echo "${1}-ssi" ;;
  *) echo "$1" ;;
  esac
}

env_key() {
  echo "E2E_IMAGE_$(echo "$1" | tr '[:lower:]-' '[:upper:]_')_$(echo "$2" | tr '[:lower:]' '[:upper:]')"
}

build_docker_image() {
  local runtime="$1"
  local mode="$2"
  local src="$EXAMPLES_DIR/$(example_dir "$runtime" "$mode")/src"
  if [ ! -f "$src/Dockerfile" ]; then
    echo "Error: missing Dockerfile at $src" >&2
    exit 1
  fi

  local img
  img="$(image_ref "$runtime" "$mode")"
  echo "====== Building ${runtime} ${mode} from ${src#"$REPO_ROOT/"} ======"
  docker build --platform linux/amd64 -t "${img}" "$src"
  docker push "${img}"
  emit "$(env_key "$runtime" "$mode")" "${img}"
}

build_pack_image() {
  local runtime="$1"
  local mode="$2"
  local src="$EXAMPLES_DIR/$(example_dir "$runtime" "$mode")/src"

  local img
  img="$(image_ref "$runtime" "$mode")"
  echo "====== Building ${runtime} ${mode} (pack) from ${src#"$REPO_ROOT/"} ======"
  gcloud builds submit --pack \
    "image=${img},env=GOOGLE_FUNCTION_TARGET=helloHttp" \
    --project "${PROJECT_ID}" \
    "$src"
  emit "$(env_key "$runtime" "$mode")" "${img}"
}

# Sidecar mode: every runtime, including go, which has no SSI path in the module.
for runtime in go node java python ruby php dotnet; do
  build_docker_image "$runtime" sidecar
done

# SSI mode: the runtimes the module can inject a tracer for.
for runtime in node java python ruby php dotnet; do
  build_docker_image "$runtime" ssi
done

# node-function builds with Cloud Buildpacks rather than a Dockerfile.
build_pack_image node-function sidecar
build_pack_image node-function ssi

echo
echo "Wrote ${OUT_FILE}"
echo "Source it before go test:"
echo "  set -a; source ${OUT_FILE}; set +a"
