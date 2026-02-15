# ------------------------------------------------------------------------------
# Network Load Balancer
# ------------------------------------------------------------------------------

resource "aws_lb" "pgdog" {
  count = var.create_resources ? 1 : 0

  name               = "${var.name}-pgdog"
  internal           = var.nlb_internal
  load_balancer_type = "network"
  subnets            = coalesce(var.nlb_subnet_ids, var.subnet_ids)

  enable_cross_zone_load_balancing = true

  tags = var.tags
}

# ------------------------------------------------------------------------------
# Target Group
# ------------------------------------------------------------------------------

resource "aws_lb_target_group" "pgdog" {
  count = var.create_resources ? 1 : 0

  name        = "${var.name}-pgdog"
  port        = local.pgdog_general.port
  protocol    = "TCP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    protocol            = "TCP"
    port                = local.pgdog_general.healthcheck_port != null ? local.pgdog_general.healthcheck_port : local.pgdog_general.port
    healthy_threshold   = 3
    unhealthy_threshold = 3
    interval            = 30
  }

  deregistration_delay = var.deregistration_delay

  tags = var.tags
}

# ------------------------------------------------------------------------------
# Listener
# ------------------------------------------------------------------------------

resource "aws_lb_listener" "pgdog" {
  count = var.create_resources ? 1 : 0

  load_balancer_arn = aws_lb.pgdog[0].arn
  port              = local.pgdog_general.port
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.pgdog[0].arn
  }

  tags = var.tags
}
