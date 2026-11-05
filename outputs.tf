output "lb_arn" {
  description = "ARN of the load balancer."
  value       = aws_lb.this.arn
}

output "lb_dns_name" {
  description = "AWS-assigned DNS name of the load balancer."
  value       = aws_lb.this.dns_name
}

output "lb_zone_id" {
  description = "Route53 zone ID of the load balancer, for alias records created outside the module."
  value       = aws_lb.this.zone_id
}

output "security_group_id" {
  description = "The load balancer's security group. Reference it from targets' ingress rules (e.g. red-instance ingress_rules[*].security_groups)."
  value       = aws_security_group.lb.id
}

output "target_group_arns" {
  description = "Target group ARNs, keyed like var.target_groups. Use these to attach targets outside the module."
  value       = { for k, tg in aws_lb_target_group.this : k => tg.arn }
}

output "listener_arns" {
  description = "Listener ARNs, keyed like var.listeners."
  value       = { for k, l in aws_lb_listener.this : k => l.arn }
}

output "certificate_arn" {
  description = "ARN of the module-created, validated certificate, or null."
  value       = try(aws_acm_certificate_validation.this[0].certificate_arn, null)
}

output "dns_records" {
  description = "FQDNs of the alias records created for the load balancer."
  value       = [for r in aws_route53_record.alias : r.fqdn]
}
