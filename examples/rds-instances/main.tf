# ------------------------------------------------------------------------------
# Example: PgDog ECS Deployment with RDS Instances (Primary + Read Replica)
# ------------------------------------------------------------------------------

provider "aws" {
  region = "us-east-1"
}

# ------------------------------------------------------------------------------
# Create password secret in Secrets Manager
# ------------------------------------------------------------------------------

resource "aws_secretsmanager_secret" "db_password" {
  name = "pgdog-rds-example/db-password"
}

resource "aws_secretsmanager_secret_version" "db_password" {
  secret_id     = aws_secretsmanager_secret.db_password.id
  secret_string = "your-secure-password-here"
}

# ------------------------------------------------------------------------------
# PgDog Module with RDS Instances
# ------------------------------------------------------------------------------

module "pgdog" {
  source = "../.."

  name = "myapp"

  # Networking
  vpc_id     = "vpc-xxxxxxxxx"
  subnet_ids = ["subnet-xxxxxxxx", "subnet-yyyyyyyy"]

  # RDS instances - module auto-detects primary/replica based on replication config
  rds_instances = [
    {
      identifier    = "myapp-primary"
      database_name = "myapp"
      role          = "auto" # Will detect as primary (no replication source)
      pool_size     = 20
    },
    {
      identifier    = "myapp-replica-1"
      database_name = "myapp"
      role          = "auto" # Will detect as replica (has replication source)
      pool_size     = 20
    },
    {
      identifier    = "myapp-replica-2"
      database_name = "myapp"
      role          = "auto"
      pool_size     = 20
    }
  ]

  # Users configuration
  users = [
    {
      name                = "app"
      database            = "myapp"
      password_secret_arn = aws_secretsmanager_secret.db_password.arn
      pool_size           = 20
      pooler_mode         = "transaction"
    }
  ]

  # PgDog configuration
  pgdog = {
    general = {
      workers                 = 4
      pooler_mode             = "transaction"
      load_balancing_strategy = "round_robin"
      read_write_strategy     = "conservative"
    }
  }

  # ECS settings
  task_cpu    = 2048
  task_memory = 4096

  # Auto-scaling
  min_capacity = 2
  max_capacity = 8

  tags = {
    Environment = "production"
    Application = "myapp"
  }
}

output "pgdog_endpoint" {
  value = module.pgdog.pgdog_endpoint
}

output "configured_databases" {
  value = module.pgdog.configured_databases
}
