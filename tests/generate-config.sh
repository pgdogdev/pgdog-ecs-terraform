#!/bin/bash
set -eo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -z "$1" ]; then
  echo "Usage: $0 <values-file> [output-dir]"
  echo "Example: $0 values-sharding.tfvars ./output"
  echo ""
  echo "Available configurations:"
  for f in "$TEST_DIR"/values-*.tfvars; do
    echo "  - $(basename "$f")"
  done
  exit 1
fi

VALUES_FILE="$1"
OUTPUT_DIR="${2:-.}"

# Handle relative paths
if [[ ! "$VALUES_FILE" = /* ]]; then
  if [[ -f "$TEST_DIR/$VALUES_FILE" ]]; then
    VALUES_FILE="$TEST_DIR/$VALUES_FILE"
  fi
fi

if [[ ! -f "$VALUES_FILE" ]]; then
  echo "Error: Values file not found: $VALUES_FILE"
  exit 1
fi

echo "==> Initializing Terraform..."
terraform -chdir="$TEST_DIR" init -backend=false > /dev/null

echo "==> Generating config from $(basename "$VALUES_FILE")..."
terraform -chdir="$TEST_DIR" apply -auto-approve -var-file="$VALUES_FILE" > /dev/null 2>&1

mkdir -p "$OUTPUT_DIR"
terraform -chdir="$TEST_DIR" output -raw pgdog_toml > "$OUTPUT_DIR/pgdog.toml"
terraform -chdir="$TEST_DIR" output -raw users_toml > "$OUTPUT_DIR/users.toml"

echo "==> Generated:"
echo "    $OUTPUT_DIR/pgdog.toml"
echo "    $OUTPUT_DIR/users.toml"

# Validate with pgdog if available
if command -v pgdog &> /dev/null; then
  echo ""
  echo "==> Validating with pgdog checkconfig..."
  pgdog checkconfig "$OUTPUT_DIR/pgdog.toml" "$OUTPUT_DIR/users.toml"
fi
