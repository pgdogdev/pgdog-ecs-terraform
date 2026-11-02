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
  terraform -chdir="$TEST_DIR" apply -auto-approve -var-file="$values_file" > /dev/null

  # Output files for inspection
  mkdir -p "$TEST_DIR/output/$name"
  terraform -chdir="$TEST_DIR" output -raw pgdog_toml > "$TEST_DIR/output/$name/pgdog.toml"
  terraform -chdir="$TEST_DIR" output -raw users_toml > "$TEST_DIR/output/$name/users.toml"

  # The init container renders users.toml at runtime. Run that script with awkward
  # passwords (quote, backslash, $, &, /) and compare with the redacted output.
  render_dir=$(mktemp -d)
  terraform -chdir="$TEST_DIR" output -raw users_init_script | sed "s#/config/#$render_dir/#g" > "$render_dir/init.sh"
  for i in 0 1 2 3; do export "USER_PASSWORD_$i"='p"a\ss$x&/' "USER_SERVER_PASSWORD_$i"='s"v\r$y&/'; done
  sh "$render_dir/init.sh"
  diff \
    <(sed -E 's/^(server_)?password = .*/\1password = "REDACTED"/' "$render_dir/users.toml" | grep -v '^$') \
    <(grep -v '^$' "$TEST_DIR/output/$name/users.toml")
  if grep -q '^password' "$render_dir/users.toml"; then
    grep -qxF 'password = "p\"a\\ss$x&/"' "$render_dir/users.toml"
  fi
  if grep -q '^server_password' "$render_dir/users.toml"; then
    grep -qxF 'server_password = "s\"v\\r$y&/"' "$render_dir/users.toml"
  fi
  rm -rf "$render_dir"

  # Validate with pgdog if available
  if command -v pgdog &> /dev/null; then
    echo "    Validating with pgdog configcheck..."
    pgdog --config "$TEST_DIR/output/$name/pgdog.toml" --users "$TEST_DIR/output/$name/users.toml" configcheck
  else
    echo "    Generated pgdog.toml and users.toml (pgdog not found, skipping validation)"
  fi

  echo "    OK"
done

echo ""
echo "==> All tests passed!"
echo "==> Generated configs are in: $TEST_DIR/output/"
