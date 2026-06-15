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
    for cp in coalesce(var.capacity_provider_strategy, []) : !contains(["FARGATE", "FARGATE_SPOT"], cp.capacity_provider)
  ])

  # Task compatibility - support both if using EC2 capacity providers
  task_compatibilities = local.uses_ec2 ? ["EC2", "FARGATE"] : ["FARGATE"]

  # TLS certificate handling scripts
  tls_script_self_signed = <<-EOF

# Generate self-signed TLS certificate
echo "$(date -Iseconds) Generating self-signed TLS certificate..."
openssl req -x509 -newkey rsa:2048 -keyout /config/server.key -out /config/server.crt \
  -days ${var.tls_self_signed_validity_days} -nodes \
  -subj "/CN=${var.tls_self_signed_common_name}" 2>/dev/null
chmod 600 /config/server.key
echo "$(date -Iseconds) TLS certificate generated"
EOF

  tls_script_secrets_manager = <<-EOF

# Write TLS certificate and key (injected from Secrets Manager by ECS)
echo "$(date -Iseconds) Writing TLS certificate..."
printf '%s' "$TLS_CERTIFICATE" > /config/server.crt

echo "$(date -Iseconds) Writing TLS private key..."
printf '%s' "$TLS_PRIVATE_KEY" > /config/server.key
chmod 600 /config/server.key
echo "$(date -Iseconds) TLS credentials written"
EOF

  tls_script = (
    var.tls_mode == "self_signed" ? local.tls_script_self_signed :
    var.tls_mode == "secrets_manager" ? local.tls_script_secrets_manager :
    ""
  )

  # Backend (e.g. RDS) CA certificate for tls_verify = verify_ca / verify_full. Provided
  # independently of tls_mode, since it secures the PgDog -> backend direction.
  ca_cert_script_body = <<-EOF

# Write backend server CA certificate (provided inline)
echo "$(date -Iseconds) Writing server CA certificate..."
printf '%s' "$TLS_SERVER_CA_CERTIFICATE" > /config/server_ca.crt
echo "$(date -Iseconds) Server CA certificate written"
EOF

  ca_cert_script = var.tls_server_ca_certificate_inline != null ? local.ca_cert_script_body : ""

  ca_cert_env_vars = var.tls_server_ca_certificate_inline != null ? [
    {
      name  = "TLS_SERVER_CA_CERTIFICATE"
      value = var.tls_server_ca_certificate_inline
    }
  ] : []

  # TLS secrets injected into the init container by ECS (secrets_manager mode)
  tls_secrets = var.tls_mode == "secrets_manager" ? [
    {
      name      = "TLS_CERTIFICATE"
      valueFrom = var.tls_certificate_secret_arn
    },
    {
      name      = "TLS_PRIVATE_KEY"
      valueFrom = var.tls_private_key_secret_arn
    }
  ] : []

  # openssl is only needed to generate a self-signed certificate on boot
  init_packages_install = var.tls_mode == "self_signed" ? "apk add --no-cache openssl > /dev/null 2>&1" : ""

  # ADOT sidecar container definition (for CloudWatch metrics export)
  adot_container = var.create_resources && var.export_metrics_to_cloudwatch ? [{
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
        "awslogs-region"        = data.aws_region.current[0].id
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
set -eo pipefail
${local.init_packages_install}
mkdir -p /config

echo "$(date -Iseconds) Writing pgdog.toml..."
printf '%s' "$PGDOG_CONFIG" > /config/pgdog.toml

echo "$(date -Iseconds) Writing users.toml..."
printf '%s' "$USERS_CONFIG" > /config/users.toml
${local.tls_script}${local.ca_cert_script}
echo "$(date -Iseconds) Done!"
EOF
        ]

        # Config (and TLS) secrets are injected natively by ECS from Secrets
        # Manager - no in-container AWS API calls or SigV4 signing required.
        secrets = concat([
          {
            name      = "PGDOG_CONFIG"
            valueFrom = aws_secretsmanager_secret.pgdog_config[0].arn
          },
          {
            name      = "USERS_CONFIG"
            valueFrom = aws_secretsmanager_secret.users_config[0].arn
          }
        ], local.tls_secrets)

        environment = local.ca_cert_env_vars

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
            "awslogs-region"        = data.aws_region.current[0].id
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

        environment = [
          {
            name  = "CONFIG_HASH"
            value = local.config_hash
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
            "awslogs-region"        = data.aws_region.current[0].id
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
    aws_iam_role_policy.task_execution_logs[0],
    aws_iam_role_policy.task_secrets[0]
  ]

  tags = var.tags
}
