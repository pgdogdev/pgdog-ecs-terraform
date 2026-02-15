# ------------------------------------------------------------------------------
# Example: PgDog ECS Deployment with Sharding Configuration
# ------------------------------------------------------------------------------

provider "aws" {
  region = "us-east-1"
}

# ------------------------------------------------------------------------------
# Secrets for database credentials
# ------------------------------------------------------------------------------

resource "aws_secretsmanager_secret" "app_password" {
  name = "pgdog-sharding/app-password"
}

resource "aws_secretsmanager_secret_version" "app_password" {
  secret_id     = aws_secretsmanager_secret.app_password.id
  secret_string = "your-secure-password-here"
}

# ------------------------------------------------------------------------------
# PgDog Module with Sharding
# ------------------------------------------------------------------------------

module "pgdog" {
  source = "../.."

  name = "sharded-app"

  # Networking
  vpc_id     = "vpc-xxxxxxxxx"
  subnet_ids = ["subnet-xxxxxxxx", "subnet-yyyyyyyy"]

  # Multiple RDS instances as shards
  rds_instances = [
    {
      identifier    = "myapp-shard-0-primary"
      database_name = "myapp"
      role          = "primary"
      pool_size     = 20
      shard         = 0
    },
    {
      identifier    = "myapp-shard-0-replica"
      database_name = "myapp"
      role          = "replica"
      pool_size     = 20
      shard         = 0
    },
    {
      identifier    = "myapp-shard-1-primary"
      database_name = "myapp"
      role          = "primary"
      pool_size     = 20
      shard         = 1
    },
    {
      identifier    = "myapp-shard-1-replica"
      database_name = "myapp"
      role          = "replica"
      pool_size     = 20
      shard         = 1
    },
  ]

  # Users configuration
  users = [
    {
      name                = "app"
      database            = "myapp"
      password_secret_arn = aws_secretsmanager_secret.app_password.arn
      pool_size           = 20
      pooler_mode         = "transaction"
    }
  ]

  # PgDog configuration with sharding
  pgdog = {
    general = {
      workers                 = 8
      pooler_mode             = "transaction"
      load_balancing_strategy = "round_robin"
      read_write_strategy     = "conservative"
    }

    tcp = {
      keepalive = true
      time      = 60
      interval  = 10
      retries   = 3
    }

    query_stats = {
      enabled     = true
      max_entries = 10000
    }

    rewrite = {
      enabled       = true
      shard_key     = "error"
      split_inserts = "error"
      primary_key   = "ignore"
    }

    sharded_tables = [
      {
        database  = "myapp"
        name      = "users"
        column    = "user_id"
        data_type = "bigint"
      },
      {
        database  = "myapp"
        name      = "orders"
        column    = "user_id"
        data_type = "bigint"
      },
      {
        database  = "myapp"
        name      = "transactions"
        column    = "user_id"
        data_type = "bigint"
      }
    ]

    sharded_mappings = [
      {
        database = "myapp"
        column   = "user_id"
        kind     = "range"
        shard    = 0
        start    = 0
        end      = 1000000
      },
      {
        database = "myapp"
        column   = "user_id"
        kind     = "range"
        shard    = 1
        start    = 1000001
        end      = 2000000
      }
    ]

    omnisharded_tables = [
      {
        database = "myapp"
        tables   = ["countries", "currencies", "settings"]
        sticky   = true
      }
    ]
  }

  # ECS settings - more resources for sharded workload
  task_cpu    = 2048
  task_memory = 4096

  # Auto-scaling
  min_capacity = 3
  max_capacity = 15

  tags = {
    Environment = "production"
    Application = "sharded-app"
  }
}

output "pgdog_endpoint" {
  value = module.pgdog.pgdog_endpoint
}

output "configured_databases" {
  value = module.pgdog.configured_databases
}
