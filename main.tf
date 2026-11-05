data "aws_vpc" "this" {
  id = var.vpc_id
}

####################################################################################################
# Security group. Rules are standalone resources (not inline) because egress
# is derived from the target groups.
resource "aws_security_group" "lb" {
  name        = "${lower(var.lb_name)}-lb-sg"
  description = "Security group for load balancer ${var.lb_name}"
  vpc_id      = var.vpc_id

  tags = merge(
    local.tags,
    { Name = "${lower(var.lb_name)}-lb-sg" },
  )
}

resource "aws_vpc_security_group_ingress_rule" "lb" {
  for_each = local.ingress_rules

  security_group_id            = aws_security_group.lb.id
  description                  = each.value.description
  ip_protocol                  = each.value.protocol
  from_port                    = each.value.protocol == "-1" ? null : each.value.from_port
  to_port                      = each.value.protocol == "-1" ? null : each.value.to_port
  cidr_ipv4                    = each.value.cidr
  referenced_security_group_id = each.value.source_sg

  tags = local.tags
}

resource "aws_vpc_security_group_egress_rule" "lb_to_targets" {
  for_each = local.egress_rules

  security_group_id = aws_security_group.lb.id
  description       = "To targets: ${upper(each.value.protocol)} ${each.value.port}"
  ip_protocol       = each.value.protocol
  from_port         = each.value.port
  to_port           = each.value.port
  cidr_ipv4         = each.value.cidr

  tags = local.tags
}

####################################################################################################
# Load balancer
# Justification: internet-facing vs internal is the caller's choice (var.internal).
# trivy:ignore:AVD-AWS-0053
resource "aws_lb" "this" {
  name               = var.lb_name
  load_balancer_type = var.load_balancer_type
  internal           = var.internal
  subnets            = var.subnet_ids
  security_groups    = [aws_security_group.lb.id]

  enable_deletion_protection       = var.enable_deletion_protection
  enable_cross_zone_load_balancing = local.is_nlb ? var.enable_cross_zone_load_balancing : null

  # ALB hardening and tuning; not applicable to NLBs.
  drop_invalid_header_fields = local.is_alb ? true : null
  idle_timeout               = local.is_alb ? var.idle_timeout : null

  dynamic "access_logs" {
    for_each = var.access_logs == null ? [] : [var.access_logs]
    content {
      bucket  = access_logs.value.bucket
      prefix  = access_logs.value.prefix
      enabled = true
    }
  }

  tags = merge(
    local.tags,
    { Name = var.lb_name },
  )
}
