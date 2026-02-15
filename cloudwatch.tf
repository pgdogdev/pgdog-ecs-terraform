# ------------------------------------------------------------------------------
# CloudWatch Log Group
# ------------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "pgdog" {
  count = var.create_resources ? 1 : 0

  name              = "/ecs/${var.name}-pgdog"
  retention_in_days = var.log_retention_days

  tags = var.tags
}
