#!/bin/bash
set -eo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Initializing Terraform..."
terraform -chdir="$TEST_DIR" init -backend=false > /dev/null

for values_file in "$TEST_DIR"/values-*.tfvars; do
  name=$(basename "$values_file" .tfvars | sed 's/values-//')
  echo ""
  echo "==> Testing $name configuration..."

  # Validate
  terraform -chdir="$TEST_DIR" validate > /dev/null

  # Generate configs
  terraform -chdir="$TEST_DIR" apply -auto-approve -var-file="$values_file" > /dev/null 2>&1

  # Output files for inspection
  mkdir -p "$TEST_DIR/output/$name"
  terraform -chdir="$TEST_DIR" output -raw pgdog_toml > "$TEST_DIR/output/$name/pgdog.toml"
  terraform -chdir="$TEST_DIR" output -raw users_toml > "$TEST_DIR/output/$name/users.toml"

  # Validate with pgdog if available
  if command -v pgdog &> /dev/null; then
    echo "    Validating with pgdog checkconfig..."
    pgdog --config "$TEST_DIR/output/$name/pgdog.toml" --users "$TEST_DIR/output/$name/users.toml" checkconfig
  else
    echo "    Generated pgdog.toml and users.toml (pgdog not found, skipping validation)"
  fi

  echo "    OK"
done

echo ""
echo "==> All tests passed!"
echo "==> Generated configs are in: $TEST_DIR/output/"
