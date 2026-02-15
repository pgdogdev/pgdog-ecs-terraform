# ------------------------------------------------------------------------------
# ECS Cluster (optional - use existing if provided)
# ------------------------------------------------------------------------------

resource "aws_ecs_cluster" "this" {
  count = var.create_resources && var.ecs_cluster_arn == null ? 1 : 0

  name = "${var.name}-pgdog"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = var.tags
}

locals {
  ecs_cluster_arn = var.create_resources ? (
    var.ecs_cluster_arn != null ? var.ecs_cluster_arn : aws_ecs_cluster.this[0].arn
  ) : ""
  ecs_cluster_name = var.create_resources ? (
    var.ecs_cluster_arn != null ? split("/", var.ecs_cluster_arn)[1] : aws_ecs_cluster.this[0].name
  ) : ""

  # Determine if using EC2 capacity providers (not FARGATE or FARGATE_SPOT)
  uses_ec2 = var.capacity_provider_strategy != null && anytrue([
    for cp in var.capacity_provider_strategy : !contains(["FARGATE", "FARGATE_SPOT"], cp.capacity_provider)
  ])

  # Task compatibility - support both if using EC2 capacity providers
  task_compatibilities = local.uses_ec2 ? ["EC2", "FARGATE"] : ["FARGATE"]

  # ADOT sidecar container definition (for CloudWatch metrics export)
  adot_container = var.export_metrics_to_cloudwatch ? [{
    name      = "adot-collector"
    image     = "public.ecr.aws/aws-observability/aws-otel-collector:latest"
    essential = false

    dependsOn = [
      {
        containerName = "pgdog"
        condition     = "START"
      }
    ]

    command = ["--config", "env:OTEL_CONFIG"]

    environment = [
      {
        name  = "OTEL_CONFIG"
        value = local.otel_config
      }
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.pgdog[0].name
        "awslogs-create-group"  = "true"
        "awslogs-region"        = data.aws_region.current.id
        "awslogs-stream-prefix" = "adot"
      }
    }
  }] : []
}

# ------------------------------------------------------------------------------
# ECS Task Definition
# ------------------------------------------------------------------------------

resource "aws_ecs_task_definition" "pgdog" {
  count = var.create_resources ? 1 : 0

  family                   = "${var.name}-pgdog"
  requires_compatibilities = local.task_compatibilities
  network_mode             = "awsvpc"
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.task_execution[0].arn
  task_role_arn            = aws_iam_role.task[0].arn

  container_definitions = jsonencode(concat(
    [
      # Init container to fetch secrets and create config files
      {
        name       = "init-config"
        image      = "public.ecr.aws/docker/library/alpine:3.19"
        essential  = false
        entryPoint = ["/bin/sh", "-c"]

        command = [<<EOF
set -e
apk add --no-cache curl jq openssl > /dev/null 2>&1

mkdir -p /config

# SigV4 signing function
sign_request() {
  local secret_arn="$1"
  local region="$AWS_REGION"
  local service="secretsmanager"
  local host="secretsmanager.$region.amazonaws.com"
  local endpoint="https://$host"
  local date_stamp=$(date -u +%Y%m%d)
  local amz_date=$(date -u +%Y%m%dT%H%M%SZ)

  # Get credentials from ECS metadata
  local creds=$(curl -s "http://169.254.170.2$AWS_CONTAINER_CREDENTIALS_RELATIVE_URI")
  local access_key=$(echo "$creds" | jq -r '.AccessKeyId')
  local secret_key=$(echo "$creds" | jq -r '.SecretAccessKey')
  local token=$(echo "$creds" | jq -r '.Token')

  # Request body
  local body="{\"SecretId\":\"$secret_arn\"}"
  local body_hash=$(printf '%s' "$body" | openssl dgst -sha256 | cut -d' ' -f2)

  # Canonical request
  local canonical_headers="content-type:application/x-amz-json-1.1\nhost:$host\nx-amz-date:$amz_date\nx-amz-security-token:$token\nx-amz-target:secretsmanager.GetSecretValue"
  local signed_headers="content-type;host;x-amz-date;x-amz-security-token;x-amz-target"
  local canonical_request="POST\n/\n\n$canonical_headers\n\n$signed_headers\n$body_hash"
  local canonical_hash=$(printf "$canonical_request" | openssl dgst -sha256 | cut -d' ' -f2)

  # String to sign
  local algorithm="AWS4-HMAC-SHA256"
  local scope="$date_stamp/$region/$service/aws4_request"
  local string_to_sign="$algorithm\n$amz_date\n$scope\n$canonical_hash"

  # Signing key
  local k_date=$(printf "$date_stamp" | openssl dgst -sha256 -hmac "AWS4$secret_key" -binary)
  local k_region=$(printf "$region" | openssl dgst -sha256 -mac HMAC -macopt hexkey:$(printf '%s' "$k_date" | xxd -p -c256) -binary)
  local k_service=$(printf "$service" | openssl dgst -sha256 -mac HMAC -macopt hexkey:$(printf '%s' "$k_region" | xxd -p -c256) -binary)
  local k_signing=$(printf "aws4_request" | openssl dgst -sha256 -mac HMAC -macopt hexkey:$(printf '%s' "$k_service" | xxd -p -c256) -binary)
  local signature=$(printf "$string_to_sign" | openssl dgst -sha256 -mac HMAC -macopt hexkey:$(printf '%s' "$k_signing" | xxd -p -c256) | cut -d' ' -f2)

  # Authorization header
  local auth_header="$algorithm Credential=$access_key/$scope, SignedHeaders=$signed_headers, Signature=$signature"

  # Make request
  curl -s "$endpoint" \
    -H "Content-Type: application/x-amz-json-1.1" \
    -H "X-Amz-Date: $amz_date" \
    -H "X-Amz-Security-Token: $token" \
    -H "X-Amz-Target: secretsmanager.GetSecretValue" \
    -H "Authorization: $auth_header" \
    -d "$body" | jq -r '.SecretString'
}

echo "$(date -Iseconds) Starting config fetch..."

echo "$(date -Iseconds) Fetching pgdog.toml..."
sign_request "$PGDOG_CONFIG_SECRET_ARN" > /config/pgdog.toml

echo "$(date -Iseconds) Fetching users.toml..."
sign_request "$USERS_CONFIG_SECRET_ARN" > /config/users.toml

echo "$(date -Iseconds) Done!"
ls -la /config/
EOF
        ]

        environment = [
          {
            name  = "PGDOG_CONFIG_SECRET_ARN"
            value = aws_secretsmanager_secret.pgdog_config[0].arn
          },
          {
            name  = "USERS_CONFIG_SECRET_ARN"
            value = aws_secretsmanager_secret.users_config[0].arn
          }
        ]

        mountPoints = [
          {
            sourceVolume  = "config"
            containerPath = "/config"
            readOnly      = false
          }
        ]

        logConfiguration = {
          logDriver = "awslogs"
          options = {
            "awslogs-group"         = aws_cloudwatch_log_group.pgdog[0].name
            "awslogs-create-group"  = "true"
            "awslogs-region"        = data.aws_region.current.id
            "awslogs-stream-prefix" = "init"
          }
        }
      },
      # Main PgDog container
      {
        name      = "pgdog"
        image     = local.pgdog_image
        essential = true

        dependsOn = [
          {
            containerName = "init-config"
            condition     = "SUCCESS"
          }
        ]

        command = [
          "pgdog",
          "--config", "/etc/pgdog/pgdog.toml",
          "--users", "/etc/pgdog/users.toml"
        ]

        portMappings = concat(
          [
            {
              containerPort = local.pgdog_general.port
              hostPort      = local.pgdog_general.port
              protocol      = "tcp"
            }
          ],
          local.pgdog_general.openmetrics_port != null ? [
            {
              containerPort = local.pgdog_general.openmetrics_port
              hostPort      = local.pgdog_general.openmetrics_port
              protocol      = "tcp"
            }
          ] : [],
          local.pgdog_general.healthcheck_port != null ? [
            {
              containerPort = local.pgdog_general.healthcheck_port
              hostPort      = local.pgdog_general.healthcheck_port
              protocol      = "tcp"
            }
          ] : []
        )

        mountPoints = [
          {
            sourceVolume  = "config"
            containerPath = "/etc/pgdog"
            readOnly      = true
          }
        ]

        healthCheck = {
          command = [
            "CMD-SHELL",
            "pg_isready -h 127.0.0.1 -p ${local.pgdog_general.port} || exit 1"
          ]
          interval    = 30
          timeout     = 5
          retries     = 3
          startPeriod = 60
        }

        logConfiguration = {
          logDriver = "awslogs"
          options = {
            "awslogs-group"         = aws_cloudwatch_log_group.pgdog[0].name
            "awslogs-create-group"  = "true"
            "awslogs-region"        = data.aws_region.current.id
            "awslogs-stream-prefix" = "pgdog"
          }
        }
      }
    ],
    # ADOT sidecar for CloudWatch metrics export (optional)
    local.adot_container
  ))

  volume {
    name = "config"
  }

  tags = var.tags
}

# ------------------------------------------------------------------------------
# ECS Service
# ------------------------------------------------------------------------------

resource "aws_ecs_service" "pgdog" {
  count = var.create_resources ? 1 : 0

  name            = "${var.name}-pgdog"
  cluster         = local.ecs_cluster_arn
  task_definition = aws_ecs_task_definition.pgdog[0].arn
  desired_count   = var.desired_count

  # Use capacity provider strategy if specified, otherwise default to FARGATE launch type
  launch_type = var.capacity_provider_strategy == null ? "FARGATE" : null

  dynamic "capacity_provider_strategy" {
    for_each = var.capacity_provider_strategy != null ? var.capacity_provider_strategy : []
    content {
      capacity_provider = capacity_provider_strategy.value.capacity_provider
      weight            = capacity_provider_strategy.value.weight
      base              = capacity_provider_strategy.value.base
    }
  }

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = concat([aws_security_group.ecs_tasks[0].id], var.security_group_ids)
    assign_public_ip = var.assign_public_ip
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.pgdog[0].arn
    container_name   = "pgdog"
    container_port   = local.pgdog_general.port
  }

  health_check_grace_period_seconds = var.health_check_grace_period

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  lifecycle {
    ignore_changes = [desired_count]
  }

  depends_on = [
    aws_lb_listener.pgdog[0],
    aws_cloudwatch_log_group.pgdog[0],
    aws_iam_role_policy.task_execution_logs[0]
  ]

  tags = var.tags
}
