# ------------------------------------------------------------------------------
# Data Sources
# ------------------------------------------------------------------------------

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

# ------------------------------------------------------------------------------
# ECS Task Execution Role
# Used by ECS to pull images and write logs
# ------------------------------------------------------------------------------

resource "aws_iam_role" "task_execution" {
  count = var.create_resources ? 1 : 0

  name = "${var.name}-pgdog-execution"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "task_execution_managed" {
  count = var.create_resources ? 1 : 0

  role       = aws_iam_role.task_execution[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Explicit CloudWatch Logs permissions for task execution role
resource "aws_iam_role_policy" "task_execution_logs" {
  count = var.create_resources ? 1 : 0

  name = "${var.name}-pgdog-execution-logs"
  role = aws_iam_role.task_execution[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = [
          aws_cloudwatch_log_group.pgdog[0].arn,
          "${aws_cloudwatch_log_group.pgdog[0].arn}:*"
        ]
      }
    ]
  })
}

# ------------------------------------------------------------------------------
# ECS Task Role
# Used by the running container to access AWS services
# ------------------------------------------------------------------------------

resource "aws_iam_role" "task" {
  count = var.create_resources ? 1 : 0

  name = "${var.name}-pgdog-task"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = var.tags
}

# Policy to read secrets from Secrets Manager
resource "aws_iam_role_policy" "task_secrets" {
  count = var.create_resources ? 1 : 0

  name = "${var.name}-pgdog-secrets"
  role = aws_iam_role.task[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = compact([
          aws_secretsmanager_secret.pgdog_config[0].arn,
          aws_secretsmanager_secret.users_config[0].arn,
          var.tls_mode == "secrets_manager" ? var.tls_certificate_secret_arn : "",
          var.tls_mode == "secrets_manager" ? var.tls_private_key_secret_arn : "",
        ])
      }
    ]
  })
}

# Policy for ADOT to write metrics to CloudWatch (EMF uses CloudWatch Logs)
resource "aws_iam_role_policy" "task_cloudwatch_metrics" {
  count = var.create_resources && var.export_metrics_to_cloudwatch ? 1 : 0

  name = "${var.name}-pgdog-cloudwatch-metrics"
  role = aws_iam_role.task[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = [
          "arn:aws:logs:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:log-group:/aws/ecs/${var.name}-pgdog/metrics",
          "arn:aws:logs:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:log-group:/aws/ecs/${var.name}-pgdog/metrics:*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "cloudwatch:namespace" = var.cloudwatch_metrics_namespace
          }
        }
      }
    ]
  })
}

# ------------------------------------------------------------------------------
# Security Group for ECS Tasks
# ------------------------------------------------------------------------------

resource "aws_security_group" "ecs_tasks" {
  count = var.create_resources ? 1 : 0

  name        = "${var.name}-pgdog-ecs"
  description = "Security group for PgDog ECS tasks"
  vpc_id      = var.vpc_id

  # Ingress from NLB on PgDog port
  ingress {
    description = "PgDog PostgreSQL port"
    from_port   = local.pgdog_general.port
    to_port     = local.pgdog_general.port
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.this[0].cidr_block]
  }

  # Ingress for metrics port (if enabled)
  dynamic "ingress" {
    for_each = local.pgdog_general.openmetrics_port != null ? [1] : []
    content {
      description = "PgDog metrics port"
      from_port   = local.pgdog_general.openmetrics_port
      to_port     = local.pgdog_general.openmetrics_port
      protocol    = "tcp"
      cidr_blocks = [data.aws_vpc.this[0].cidr_block]
    }
  }

  # Health check port if different
  dynamic "ingress" {
    for_each = local.pgdog_general.healthcheck_port != null ? [1] : []
    content {
      description = "PgDog health check port"
      from_port   = local.pgdog_general.healthcheck_port
      to_port     = local.pgdog_general.healthcheck_port
      protocol    = "tcp"
      cidr_blocks = [data.aws_vpc.this[0].cidr_block]
    }
  }

  # Egress to anywhere (needed for RDS, Secrets Manager, ECR)
  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.name}-pgdog-ecs"
  })
}

data "aws_vpc" "this" {
  count = var.create_resources ? 1 : 0

  id = var.vpc_id
}
