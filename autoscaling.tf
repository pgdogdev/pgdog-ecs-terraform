# ------------------------------------------------------------------------------
# Application Auto Scaling Target
# ------------------------------------------------------------------------------

resource "aws_appautoscaling_target" "pgdog" {
  count = var.create_resources ? 1 : 0

  max_capacity       = var.max_capacity
  min_capacity       = var.min_capacity
  resource_id        = "service/${local.ecs_cluster_name}/${aws_ecs_service.pgdog[0].name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

# ------------------------------------------------------------------------------
# CPU Target Tracking Policy
# ------------------------------------------------------------------------------

resource "aws_appautoscaling_policy" "cpu" {
  count = var.create_resources ? 1 : 0

  name               = "${var.name}-pgdog-cpu"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.pgdog[0].resource_id
  scalable_dimension = aws_appautoscaling_target.pgdog[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.pgdog[0].service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }

    target_value       = var.cpu_target_value
    scale_in_cooldown  = var.scale_in_cooldown
    scale_out_cooldown = var.scale_out_cooldown
  }
}

# ------------------------------------------------------------------------------
# Memory Target Tracking Policy
# ------------------------------------------------------------------------------

resource "aws_appautoscaling_policy" "memory" {
  count = var.create_resources ? 1 : 0

  name               = "${var.name}-pgdog-memory"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.pgdog[0].resource_id
  scalable_dimension = aws_appautoscaling_target.pgdog[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.pgdog[0].service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageMemoryUtilization"
    }

    target_value       = var.memory_target_value
    scale_in_cooldown  = var.scale_in_cooldown
    scale_out_cooldown = var.scale_out_cooldown
  }
}
