# PgDog ECS Terraform Module

Deploys [PgDog](https://pgdog.dev) on AWS ECS. Both Fargate and EC2 clusters are supported, with Fargate used by default.

## Features

:heavy_check_mark: ECS service with load balancer and CPU autoscaling

:heavy_check_mark: Secure configuration storage in Secrets Manager

:heavy_check_mark: PgDog logs and metrics export to CloudWatch

:heavy_check_mark: Automatic RDS instance detection, including Aurora readers & writer

:heavy_check_mark: Guaranteed QoS with preconfigured CPU and memory requirements

## Quick start

Add this module to your Terraform workspace. If you have an existing RDS Postgres or Aurora database, the module can import it automatically and add it to the `[[databases]]` section in `pgdog.toml`, for example:

```hcl
module "pgdog" {
  source = "github.com/pgdogdev/pgdog-ecs-terraform"

  # The module will automatically detect all instances
  # and add them to pgdog.toml.
  aurora_clusters = [
    {
      cluster_identifier = "aurora-cluster-name"
      database_name      = "postgres"
    }
  ]

  # Users need to be configured manually.
  users = [
    {
      name                = "postgres"
      database            = "postgres" # Must match database_name above.
      # Password is securely stored in AWS Secrets Manager.
      password_secret_arn = aws_secretsmanager_secret.postgres_user_password.arn
    }
  ]

  # You have a ECS cluster already?
  ecs_cluster_arn = "arn:aws:ecs:us-west-2:1234567890:cluster/your-fargate-ecs-cluster"

  # Networking configuration.
  vpc_id     = "vpc-xxxxxxxxxx"
  subnet_ids = ["subnet-xxxxxxxxxx", "subnet-yyyyyyyyyyy"]

  pgdog = {
    # PgDog version.
    image_tag = "v0.1.29"
    
    # Configure any pgdog.toml settings directly in TF.
    general = {
      workers = 2
    }
  }
}
```

The password for each user needs to be stored in Secrets Manager. You can do so manually or by using Terraform:

```hcl
resource "aws_secretsmanager_secret" "postgres_user_password" {
  name = "your-pgdog-deployment/postgres-password"
}

resource "aws_secretsmanager_secret_version" "postgres_user_password" {
  secret_id     = aws_secretsmanager_secret.postgres_user_password.id

  # Store the password in Vault or another secrets manager, e.g. 1Password.
  secret_string = "${data.vault_kv_secret_v2.db.data["password"]}"
}
```

## Dependencies

Tasks created by the ECS service require access to the Internet to download container images and push metrics and logs to CloudWatch. To make this work out of the box, you have two options:

1. Use **private** `subnet_ids` which have an attached **NAT gateway**
2. Use **public** `subnet_ids` and assign ECS tasks **public IPs** by configuring `assign_public_ip = true`

Failure to do either will produce confusing errors at task creation, since it won't be able to log errors to CloudWatch or pull container images.

## Managed resources

| Resource | Description |
|----------|-------------|
| ECS Cluster | Optional, only if `ecs_cluster_arn` not provided. |
| ECS task definition | PgDog container, init container to setup configuration, and optional ADOT sidecar to export Prometheus metrics to CloudWatch. |
| ECS service | Supports deployment circuit breaker and rolling deployments. |
| Network load balancer | Your application will connect to the load balancer. |
| Security group | For controlling ingress to ECS tasks. |
| IAM Roles | Automatically configured task execution and task runtime roles. |
| Secrets Manager Secrets | Storing `pgdog.toml` and `users.toml` configuration files. |
| CloudWatch Log Group | PgDog container logs. |
| Autoscaling | Target and policies (CPU/memory-based). |

## Variables

### General

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| `name` | Name prefix for all resources | `string` | - | yes |
| `create_resources` | Whether to create AWS resources (set to false for config-only testing) | `bool` | `true` | no |
| `tags` | Tags to apply to all resources | `map(string)` | `{}` | no |

```hcl
module "pgdog" {
  source = "github.com/pgdogdev/pgdog-ecs-terraform"
  name   = "myapp"
  tags   = { Environment = "prod" }
}
```

### Networking

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| `vpc_id` | VPC ID where ECS tasks will run | `string` | - | yes |
| `subnet_ids` | Subnet IDs for ECS tasks | `list(string)` | - | yes |
| `assign_public_ip` | Assign public IP to ECS tasks (required if using public subnets without NAT Gateway) | `bool` | `false` | no |
| `security_group_ids` | Additional security group IDs to attach to ECS tasks | `list(string)` | `[]` | no |
| `nlb_subnet_ids` | Subnet IDs for NLB (defaults to var.subnet_ids if not specified) | `list(string)` | `null` | no |
| `nlb_internal` | Whether the NLB should be internal | `bool` | `true` | no |

```hcl
vpc_id           = "vpc-123456"
subnet_ids       = ["subnet-a", "subnet-b"]
assign_public_ip = true
```

### RDS configuration

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| `databases` | Direct database configuration (alternative to rds_instances/aurora_clusters) | `list(object)` | `[]` | no |
| `rds_instances` | List of RDS instance identifiers to configure as databases | `list(object)` | `[]` | no |
| `aurora_clusters` | List of Aurora cluster identifiers to configure as databases | `list(object)` | `[]` | no |

```hcl
# Option 1: Direct database configuration
databases = [
  { name = "mydb", host = "primary.example.com", role = "primary" },
  { name = "mydb", host = "replica.example.com", role = "replica" }
]

# Option 2: Auto-discover from RDS
rds_instances = [
  { identifier = "mydb-primary", database_name = "mydb" }
]

# Option 3: Auto-discover from Aurora (uses instance endpoints with automatic role detection)
aurora_clusters = [
  { cluster_identifier = "my-cluster", database_name = "mydb" }
]
```

### PgDog users

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| `users` | PgDog users configuration | `list(object)` | - | yes |
| `users[].name` | Username for client authentication | `string` | - | yes |
| `users[].database` | Database name this user can connect to | `string` | - | yes |
| `users[].password_secret_arn` | ARN of Secrets Manager secret containing the password | `string` | - | yes |
| `users[].server_user` | Username for connecting to the backend database (if different) | `string` | `null` | no |
| `users[].server_password_secret_arn` | ARN of secret for backend database password (if different) | `string` | `null` | no |
| `users[].pool_size` | Connection pool size for this user | `number` | `10` | no |
| `users[].pooler_mode` | Pooler mode (transaction/session/statement) | `string` | `transaction` | no |

```hcl
users = [
  {
    name                = "app"
    database            = "mydb"
    password_secret_arn = "arn:aws:secretsmanager:us-east-1:123456789:secret:app-password"
    pool_size           = 20
  },
  {
    name                = "migrations"
    database            = "mydb"
    password_secret_arn = "arn:aws:secretsmanager:us-east-1:123456789:secret:migrations-password"
  }
]
```

### PgDog configuration

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| `pgdog` | PgDog configuration - mirrors pgdog.toml structure | `object` | `{}` | no |
| `pgdog.image_repository` | Container image repository | `string` | `ghcr.io/pgdogdev/pgdog` | no |
| `pgdog.image_tag` | Container image tag | `string` | `0.1.29` | no |
| `pgdog.general` | [General settings](https://docs.pgdog.dev/configuration/pgdog.toml/general/) | `object` | `{}` | no |
| `pgdog.tls` | TLS settings | `object` | `null` | no |
| `pgdog.tcp` | [TCP settings](https://docs.pgdog.dev/configuration/pgdog.toml/network/) | `object` | `null` | no |
| `pgdog.memory` | Memory settings | `object` | `null` | no |
| `pgdog.admin` | [Admin settings](https://docs.pgdog.dev/configuration/pgdog.toml/admin/) | `object` | `null` | no |
| `pgdog.query_stats` | Query stats settings | `object` | `null` | no |
| `pgdog.rewrite` | [Rewrite settings](https://docs.pgdog.dev/configuration/pgdog.toml/rewrite/) | `object` | `null` | no |
| `pgdog.control` | Control plane settings (endpoint, token, intervals) | `object` | `null` | no |
| `pgdog.sharded_tables` | [Sharded tables](https://docs.pgdog.dev/configuration/pgdog.toml/sharded_tables/) | `list(object)` | `[]` | no |
| `pgdog.sharded_schemas` | [Sharded schemas](https://docs.pgdog.dev/configuration/pgdog.toml/sharded_schemas/) | `list(object)` | `[]` | no |
| `pgdog.sharded_mappings` | Sharded mappings | `list(object)` | `[]` | no |
| `pgdog.omnisharded_tables` | Omnisharded tables | `list(object)` | `[]` | no |
| `pgdog.mirrors` | [Mirroring config](https://docs.pgdog.dev/configuration/pgdog.toml/mirroring/) | `list(object)` | `[]` | no |

```hcl
pgdog = {
  general = {
    workers       = 4
    query_timeout = 30000
  }
}
```

### ECS configuration

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| `ecs_cluster_arn` | Existing ECS cluster ARN (if not provided, a new cluster will be created) | `string` | `null` | no |
| `task_cpu` | CPU units for the task (256, 512, 1024, 2048, 4096) | `number` | `1024` | no |
| `task_memory` | Memory in MB for the task | `number` | `2048` | no |
| `desired_count` | Desired number of ECS tasks | `number` | `2` | no |
| `min_capacity` | Minimum number of ECS tasks for auto-scaling | `number` | `2` | no |
| `max_capacity` | Maximum number of ECS tasks for auto-scaling | `number` | `10` | no |
| `capacity_provider_strategy` | Capacity provider strategy (if not set, uses FARGATE launch type) | `list(object)` | `null` | no |

```hcl
# Default: Fargate
task_cpu      = 2048
task_memory   = 4096
desired_count = 3

# EC2 capacity provider (managed instances)
capacity_provider_strategy = [
  { capacity_provider = "my-ec2-capacity-provider", weight = 1 }
]

# Mixed Fargate + Fargate Spot
capacity_provider_strategy = [
  { capacity_provider = "FARGATE", weight = 1, base = 1 },
  { capacity_provider = "FARGATE_SPOT", weight = 4 }
]
```

### Logging

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| `log_retention_days` | CloudWatch log retention in days | `number` | `30` | no |

```hcl
log_retention_days = 7
```

### ECS health check

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| `health_check_grace_period` | Seconds to wait before starting health checks on a new task | `number` | `60` | no |
| `deregistration_delay` | Seconds to wait before deregistering a target from the NLB | `number` | `30` | no |

```hcl
health_check_grace_period = 120
deregistration_delay      = 60
```

### CloudWatch metrics export

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| `export_metrics_to_cloudwatch` | Export PgDog Prometheus metrics to CloudWatch using ADOT sidecar | `bool` | `true` | no |
| `cloudwatch_metrics_namespace` | CloudWatch metrics namespace for PgDog metrics | `string` | `PgDog` | no |
| `metrics_collection_interval` | How often to scrape metrics (in seconds) | `number` | `60` | no |

```hcl
export_metrics_to_cloudwatch = true
cloudwatch_metrics_namespace = "MyApp/PgDog"
metrics_collection_interval  = 30
```

### TLS configuration

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| `tls_mode` | TLS mode: disabled, self_signed, or secrets_manager | `string` | `disabled` | no |
| `tls_certificate_secret_arn` | ARN of secret containing TLS certificate (when tls_mode = secrets_manager) | `string` | `null` | no |
| `tls_private_key_secret_arn` | ARN of secret containing TLS private key (when tls_mode = secrets_manager) | `string` | `null` | no |
| `tls_self_signed_common_name` | Common name for self-signed certificate | `string` | `pgdog` | no |
| `tls_self_signed_validity_days` | Validity period for self-signed certificate | `number` | `365` | no |

```hcl
# Self-signed certificate (generated on boot)
tls_mode = "self_signed"

# Certificate from Secrets Manager
tls_mode                   = "secrets_manager"
tls_certificate_secret_arn = "arn:aws:secretsmanager:us-east-1:123456789:secret:pgdog-cert"
tls_private_key_secret_arn = "arn:aws:secretsmanager:us-east-1:123456789:secret:pgdog-key"
```
