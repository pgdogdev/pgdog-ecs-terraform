# ------------------------------------------------------------------------------
# Test Module - Uses the main module with mock data (no AWS required)
# ------------------------------------------------------------------------------

variable "test_name" {
  description = "Name of the test configuration"
  type        = string
  default     = "test"
}

variable "databases" {
  description = "Mock database configurations"
  type = list(object({
    name      = string
    host      = string
    port      = optional(number, 5432)
    pool_size = optional(number)
    role      = optional(string, "primary")
    shard     = optional(number, 0)
  }))
  default = []
}

variable "users" {
  description = "User configurations"
  type = list(object({
    name                       = string
    database                   = string
    password_secret_arn        = optional(string, "arn:aws:secretsmanager:us-east-1:123456789:secret:test")
    server_user                = optional(string)
    server_password_secret_arn = optional(string)
    pool_size                  = optional(number)
    pooler_mode                = optional(string, "transaction")
    read_only                  = optional(bool, false)
  }))
  default = []
}

variable "pgdog" {
  description = "PgDog configuration"
  type        = any
  default     = {}
}

# ------------------------------------------------------------------------------
# Use the actual module with test-only mode
# ------------------------------------------------------------------------------

module "pgdog" {
  source = "./.."

  name       = var.test_name
  vpc_id     = "vpc-test"
  subnet_ids = ["subnet-test"]

  # Use direct databases (no AWS lookups)
  databases = var.databases

  users = var.users
  pgdog = var.pgdog

  # Skip resource creation for testing
  create_resources = false
}

# ------------------------------------------------------------------------------
# Outputs
# ------------------------------------------------------------------------------

output "pgdog_toml" {
  value = module.pgdog.pgdog_toml
}

output "users_toml" {
  value = module.pgdog.users_toml
}

output "test_name" {
  value = var.test_name
}
