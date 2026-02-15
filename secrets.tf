# ------------------------------------------------------------------------------
# Secrets Manager - PgDog Configuration
# ------------------------------------------------------------------------------

resource "aws_secretsmanager_secret" "pgdog_config" {
  count = var.create_resources ? 1 : 0

  name        = "${var.name}-pgdog-config"
  description = "PgDog configuration (pgdog.toml)"

  tags = var.tags
}

resource "aws_secretsmanager_secret_version" "pgdog_config" {
  count = var.create_resources ? 1 : 0

  secret_id     = aws_secretsmanager_secret.pgdog_config[0].id
  secret_string = local.pgdog_toml
}

resource "aws_secretsmanager_secret" "users_config" {
  count = var.create_resources ? 1 : 0

  name        = "${var.name}-pgdog-users"
  description = "PgDog users configuration (users.toml)"

  tags = var.tags
}

resource "aws_secretsmanager_secret_version" "users_config" {
  count = var.create_resources ? 1 : 0

  secret_id     = aws_secretsmanager_secret.users_config[0].id
  secret_string = local.users_toml
}

# ------------------------------------------------------------------------------
# Locals for secret ARNs used by ECS task
# ------------------------------------------------------------------------------

locals {
  # Collect all password secret ARNs that need to be accessible
  user_password_secret_arns = [
    for user in var.users : user.password_secret_arn
  ]

  server_password_secret_arns = [
    for user in var.users : user.server_password_secret_arn
    if user.server_password_secret_arn != null
  ]

  all_password_secret_arns = concat(
    local.user_password_secret_arns,
    local.server_password_secret_arns
  )
}
