# ------------------------------------------------------------------------------
# Configuration File Outputs (always available)
# ------------------------------------------------------------------------------

output "pgdog_toml" {
  description = "Generated pgdog.toml content for validation with 'pgdog checkconfig'"
  value       = local.pgdog_toml
}

output "users_toml" {
  description = "Generated users.toml content (secrets replaced with PLACEHOLDER) for validation"
  value       = replace(local.users_toml, "/\\{\\{SECRET:[^}]+\\}\\}/", "PLACEHOLDER")
}

output "configured_databases" {
  description = "List of configured databases with their roles"
  value = [
    for db in local.all_databases : {
      name       = db.name
      host       = db.host
      port       = db.port
      role       = db.role
      identifier = db.identifier
      shard      = db.shard
    }
  ]
}

# ------------------------------------------------------------------------------
# Network Load Balancer Outputs (only when resources are created)
# ------------------------------------------------------------------------------

output "nlb_dns_name" {
  description = "DNS name of the Network Load Balancer"
  value       = var.create_resources ? aws_lb.pgdog[0].dns_name : null
}

output "nlb_arn" {
  description = "ARN of the Network Load Balancer"
  value       = var.create_resources ? aws_lb.pgdog[0].arn : null
}

output "nlb_zone_id" {
  description = "Zone ID of the Network Load Balancer (for Route53 alias records)"
  value       = var.create_resources ? aws_lb.pgdog[0].zone_id : null
}

output "pgdog_endpoint" {
  description = "PgDog connection endpoint (host:port)"
  value       = var.create_resources ? "${aws_lb.pgdog[0].dns_name}:${local.pgdog_general.port}" : null
}

# ------------------------------------------------------------------------------
# ECS Outputs (only when resources are created)
# ------------------------------------------------------------------------------

output "ecs_cluster_arn" {
  description = "ARN of the ECS cluster"
  value       = var.create_resources ? local.ecs_cluster_arn : null
}

output "ecs_cluster_name" {
  description = "Name of the ECS cluster"
  value       = var.create_resources ? local.ecs_cluster_name : null
}

output "ecs_service_name" {
  description = "Name of the ECS service"
  value       = var.create_resources ? aws_ecs_service.pgdog[0].name : null
}

output "ecs_service_arn" {
  description = "ARN of the ECS service"
  value       = var.create_resources ? aws_ecs_service.pgdog[0].id : null
}

output "task_definition_arn" {
  description = "ARN of the ECS task definition"
  value       = var.create_resources ? aws_ecs_task_definition.pgdog[0].arn : null
}

# ------------------------------------------------------------------------------
# Security Outputs (only when resources are created)
# ------------------------------------------------------------------------------

output "security_group_id" {
  description = "ID of the security group for ECS tasks"
  value       = var.create_resources ? aws_security_group.ecs_tasks[0].id : null
}

output "task_role_arn" {
  description = "ARN of the ECS task role"
  value       = var.create_resources ? aws_iam_role.task[0].arn : null
}

output "task_execution_role_arn" {
  description = "ARN of the ECS task execution role"
  value       = var.create_resources ? aws_iam_role.task_execution[0].arn : null
}

# ------------------------------------------------------------------------------
# Secrets Manager Outputs (only when resources are created)
# ------------------------------------------------------------------------------

output "config_secret_arn" {
  description = "ARN of the Secrets Manager secret containing pgdog.toml"
  value       = var.create_resources ? aws_secretsmanager_secret.pgdog_config[0].arn : null
}

# ------------------------------------------------------------------------------
# CloudWatch Outputs (only when resources are created)
# ------------------------------------------------------------------------------

output "log_group_name" {
  description = "Name of the CloudWatch log group"
  value       = var.create_resources ? aws_cloudwatch_log_group.pgdog[0].name : null
}

output "log_group_arn" {
  description = "ARN of the CloudWatch log group"
  value       = var.create_resources ? aws_cloudwatch_log_group.pgdog[0].arn : null
}
