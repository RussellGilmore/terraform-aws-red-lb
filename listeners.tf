resource "aws_lb_listener" "this" {
  for_each = var.listeners

  load_balancer_arn = aws_lb.this.arn
  port              = each.value.port
  protocol          = each.value.protocol

  # HTTPS/TLS only: the listener's own certificate, else the module-created one.
  certificate_arn = contains(["HTTPS", "TLS"], each.value.protocol) ? try(
    coalesce(each.value.certificate_arn, aws_acm_certificate_validation.this[0].certificate_arn),
    null
  ) : null

  ssl_policy = contains(["HTTPS", "TLS"], each.value.protocol) ? coalesce(each.value.ssl_policy, var.default_ssl_policy) : null

  default_action {
    type             = each.value.redirect_to_https ? "redirect" : "forward"
    target_group_arn = each.value.redirect_to_https ? null : try(aws_lb_target_group.this[each.value.target_group].arn, null)

    dynamic "redirect" {
      for_each = each.value.redirect_to_https ? [1] : []
      content {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }
  }

  tags = merge(
    local.tags,
    { Name = "${var.lb_name}-${each.key}" },
  )
}
