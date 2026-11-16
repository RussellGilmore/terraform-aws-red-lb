resource "aws_lb_target_group" "this" {
  for_each = var.target_groups

  name        = local.target_group_names[each.key]
  port        = each.value.port
  protocol    = each.value.protocol
  target_type = each.value.target_type
  vpc_id      = var.vpc_id

  deregistration_delay              = each.value.deregistration_delay
  load_balancing_cross_zone_enabled = each.value.cross_zone == null ? null : tostring(each.value.cross_zone)
  preserve_client_ip                = each.value.preserve_client_ip == null ? null : tostring(each.value.preserve_client_ip)

  health_check {
    enabled             = true
    protocol            = local.health_protocols[each.key]
    port                = each.value.health_check.port
    path                = contains(["HTTP", "HTTPS"], local.health_protocols[each.key]) ? each.value.health_check.path : null
    matcher             = contains(["HTTP", "HTTPS"], local.health_protocols[each.key]) ? each.value.health_check.matcher : null
    interval            = each.value.health_check.interval
    timeout             = each.value.health_check.timeout
    healthy_threshold   = each.value.health_check.healthy_threshold
    unhealthy_threshold = each.value.health_check.unhealthy_threshold
  }

  tags = merge(
    local.tags,
    { Name = "${var.lb_name}-${each.key}" },
  )

  # A listener can't be left pointing at a deleted target group, so the
  # replacement is created first and the listener repointed before the old
  # group is destroyed. The hashed name keeps the two from colliding.
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb_target_group_attachment" "this" {
  for_each = local.target_attachments

  target_group_arn = aws_lb_target_group.this[each.value.tg_key].arn
  target_id        = each.value.id
  port             = each.value.port

  # Register targets with a replacement target group before deregistering
  # them from the old one.
  lifecycle {
    create_before_destroy = true
  }
}
