# ------------------------------------------------------------------------------
# Example: PgDog ECS Deployment with Aurora Cluster
# ------------------------------------------------------------------------------

provider "aws" {
  region = "us-east-1"
}

# ------------------------------------------------------------------------------
# Create password secrets in Secrets Manager
# ------------------------------------------------------------------------------

resource "aws_secretsmanager_secret" "app_password" {
  name = "pgdog-example/app-password"
}

resource "aws_secretsmanager_secret_version" "app_password" {
  secret_id     = aws_secretsmanager_secret.app_password.id
  secret_string = "your-secure-password-here"
}

resource "aws_secretsmanager_secret" "readonly_password" {
  name = "pgdog-example/readonly-password"
}

resource "aws_secretsmanager_secret_version" "readonly_password" {
  secret_id     = aws_secretsmanager_secret.readonly_password.id
  secret_string = "your-readonly-password-here"
}

# ------------------------------------------------------------------------------
# PgDog Module
# ------------------------------------------------------------------------------

module "pgdog" {
  source = "../.."

  name = "myapp"

  # Networking - use your existing VPC
  vpc_id     = "vpc-xxxxxxxxx"
  subnet_ids = ["subnet-xxxxxxxx", "subnet-yyyyyyyy"]

  # Aurora cluster - module will auto-configure primary and replica
  aurora_clusters = [
    {
      cluster_identifier = "myapp-aurora-cluster"
      database_name      = "myapp"
      pool_size          = 20
    }
  ]

  # Users configuration
  users = [
    {
      name                = "app"
      database            = "myapp"
      password_secret_arn = aws_secretsmanager_secret.app_password.arn
      pool_size           = 20
      pooler_mode         = "transaction"
    },
    {
      name                = "readonly"
      database            = "myapp"
      password_secret_arn = aws_secretsmanager_secret.readonly_password.arn
      pool_size           = 10
      pooler_mode         = "transaction"
      read_only           = true
    }
  ]

  # PgDog configuration
  pgdog = {
    general = {
      workers           = 4
      pooler_mode       = "transaction"
      default_pool_size = 10
    }
  }

  # ECS settings
  task_cpu      = 1024
  task_memory   = 2048
  desired_count = 2

  # Auto-scaling
  min_capacity     = 2
  max_capacity     = 10
  cpu_target_value = 70

  # NLB
  nlb_internal = true

  tags = {
    Environment = "production"
    Application = "myapp"
  }
}

# ------------------------------------------------------------------------------
# Outputs
# ------------------------------------------------------------------------------

output "pgdog_endpoint" {
  description = "PgDog connection endpoint"
  value       = module.pgdog.pgdog_endpoint
}

output "nlb_dns_name" {
  description = "NLB DNS name"
  value       = module.pgdog.nlb_dns_name
}

output "configured_databases" {
  description = "Databases configured in PgDog"
  value       = module.pgdog.configured_databases
}
