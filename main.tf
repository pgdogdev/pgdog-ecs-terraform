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
}

# ------------------------------------------------------------------------------
# ECS Task Definition
# ------------------------------------------------------------------------------

resource "aws_ecs_task_definition" "pgdog" {
  count = var.create_resources ? 1 : 0

  family                   = "${var.name}-pgdog"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.task_execution[0].arn
  task_role_arn            = aws_iam_role.task[0].arn

  container_definitions = jsonencode([
    # Init container to fetch secrets and create config files
    {
      name      = "init-config"
      image     = "amazon/aws-cli:latest"
      essential = false

      command = [
        "/bin/sh", "-c",
        <<-EOT
        set -e
        mkdir -p /config

        echo "Fetching pgdog.toml from Secrets Manager..."
        aws secretsmanager get-secret-value \
          --secret-id "$PGDOG_CONFIG_SECRET_ARN" \
          --query SecretString \
          --output text > /config/pgdog.toml

        echo "Fetching users.toml template from Secrets Manager..."
        aws secretsmanager get-secret-value \
          --secret-id "$USERS_CONFIG_SECRET_ARN" \
          --query SecretString \
          --output text > /config/users.toml

        echo "Replacing secret placeholders with actual values..."
        grep -oE '\{\{SECRET:[^}]+\}\}' /config/users.toml | sort -u | while read -r placeholder; do
          secret_arn=$(echo "$placeholder" | sed 's/{{SECRET:\(.*\)}}/\1/')
          secret_value=$(aws secretsmanager get-secret-value \
            --secret-id "$secret_arn" \
            --query SecretString \
            --output text)
          escaped_value=$(printf '%s\n' "$secret_value" | sed 's/[&/\]/\\&/g')
          sed -i "s|$placeholder|$escaped_value|g" /config/users.toml
        done

        echo "Configuration files created:"
        ls -la /config/
        echo "Done!"
        EOT
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
          },
          {
            containerPort = local.pgdog_general.metrics_port
            hostPort      = local.pgdog_general.metrics_port
            protocol      = "tcp"
          }
        ],
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
          "awslogs-region"        = data.aws_region.current.id
          "awslogs-stream-prefix" = "pgdog"
        }
      }
    }
  ])

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
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = concat([aws_security_group.ecs_tasks[0].id], var.security_group_ids)
    assign_public_ip = false
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
    aws_lb_listener.pgdog[0]
  ]

  tags = var.tags
}
