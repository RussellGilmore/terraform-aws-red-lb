resource "aws_route53_record" "alias" {
  for_each = toset(var.dns_records)

  zone_id = data.aws_route53_zone.this[0].zone_id
  name    = each.value
  type    = "A"

  alias {
    name                   = aws_lb.this.dns_name
    zone_id                = aws_lb.this.zone_id
    evaluate_target_health = var.dns_evaluate_target_health
  }
}
