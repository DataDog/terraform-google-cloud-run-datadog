#!/usr/bin/env bash

# Script for destroying terraform-deployed Cloud Run apps
# Usage: ./destroy.sh <language>
# Example: ./destroy.sh go

set -auo pipefail

if ! command -v terraform &> /dev/null; then
    echo "Error: terraform command not found. Please install Terraform."
    exit 1
fi

if [ $# -ne 1 ]; then
    echo "Usage: $0 <language>"
    echo "Available languages: go, python, node, java, php, ruby, dotnet"
    exit 1
fi

LANGUAGE="$1"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_PATH="$SCRIPT_DIR/$LANGUAGE"

if [ ! -d "$PROJECT_PATH" ]; then
    echo "Error: Language directory '$LANGUAGE' not found in $SCRIPT_DIR"
    exit 1
fi


echo -e "\n====== Destroying $LANGUAGE example ======"

cd "$PROJECT_PATH"

terraform destroy -auto-approve

echo -e "\n====== Done! ======"