# terraform-aws-red-lb

Terraform module for an AWS Network Load Balancer (NLB) or Application Load
Balancer (ALB), with its own security group, target groups, listeners, and
optional public DNS and ACM certificate.

## Features

- One module for both load balancer types (`load_balancer_type`)
- Dedicated security group: ingress from CIDRs and/or source security groups
  (same `ingress_rules` shape as red-instance); egress derived automatically
  from the target groups' ports and health checks
- Target groups with optional in-module target attachments, or ARNs output for
  attaching targets elsewhere (e.g. an Auto Scaling group)
- Listeners that forward to a target group or, on ALB HTTP listeners, redirect
  to HTTPS
- TLS 1.3 security policy by default on HTTPS/TLS listeners
- ALB hardening: invalid header fields are dropped
- Optional public ACM certificate for ALBs, DNS-validated in Route53
- Optional Route53 alias records
- Optional access logs to an existing S3 bucket (off by default)

## Usage

### NLB in front of instances

Targets admit traffic from the load balancer's security group rather than from
CIDRs, so they are never directly reachable on the forwarded ports.

```hcl
module "nlb" {
  source = "git::https://github.com/RussellGilmore/terraform-aws-red-lb.git?ref=v1.0.0"

  project_name       = "my-project"
  lb_name            = "my-nlb"
  load_balancer_type = "network"
  vpc_id             = module.network.vpc_id
  subnet_ids         = values(module.network.subnet_ids)

  ingress_rules = [
    { description = "HTTPS from anywhere", from_port = 443, to_port = 443, protocol = "tcp", cidr_blocks = ["0.0.0.0/0"] },
  ]

  target_groups = {
    https = {
      port     = 443
      protocol = "TCP"
      targets  = { for k, m in module.workers : k => { id = m.instance_id } }
    }
  }

  listeners = {
    https = { port = 443, protocol = "TCP", target_group = "https" }
  }

  apex_domain = "example.com"
  dns_records = ["app.example.com"]
}

module "worker" {
  source = "git::https://github.com/RussellGilmore/terraform-aws-red-instance.git?ref=v2.5.0"
  # ...
  ingress_rules = [
    { description = "HTTPS from the NLB", from_port = 443, to_port = 443, protocol = "tcp", security_groups = [module.nlb.security_group_id] },
  ]
}
```

### ALB with a managed certificate and HTTP-to-HTTPS redirect

```hcl
module "alb" {
  source = "git::https://github.com/RussellGilmore/terraform-aws-red-lb.git?ref=v1.0.0"

  project_name       = "my-project"
  lb_name            = "my-alb"
  load_balancer_type = "application"
  vpc_id             = module.network.vpc_id
  subnet_ids         = values(module.network.subnet_ids) # at least two AZs

  ingress_rules = [
    { description = "HTTP from anywhere", from_port = 80, to_port = 80, protocol = "tcp", cidr_blocks = ["0.0.0.0/0"] },
    { description = "HTTPS from anywhere", from_port = 443, to_port = 443, protocol = "tcp", cidr_blocks = ["0.0.0.0/0"] },
  ]

  target_groups = {
    web = {
      port         = 8080
      protocol     = "HTTP"
      health_check = { path = "/healthz" }
    }
  }

  listeners = {
    http  = { port = 80, protocol = "HTTP", redirect_to_https = true }
    https = { port = 443, protocol = "HTTPS", target_group = "web" }
  }

  # HTTPS listeners without their own certificate_arn use this certificate.
  create_certificate      = true
  certificate_domain_name = "app.example.com"
  apex_domain             = "example.com"
  dns_records             = ["app.example.com"]
}
```

## Notes

- **Names:** target groups are named `<lb_name>-<key>`, and AWS limits load
  balancer and target group names to 32 characters. Validation checks this at
  plan time.
- **Client IPs:** NLB instance targets preserve client IPs by default. Target
  security groups should reference the load balancer's security group
  (`security_group_id`) rather than allowing the internet.
- **Cross-zone:** NLBs default to in-zone routing. Set `cross_zone = true` on a
  target group whose targets don't cover every AZ the NLB is in.
- **Egress:** the security group only allows traffic to the target groups' ports
  in the VPC CIDR. Set `target_cidr_blocks` for IP targets elsewhere.

<!-- prettier-ignore-start -->
<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.15.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.47.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | >= 6.47.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_acm_certificate.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/acm_certificate) | resource |
| [aws_acm_certificate_validation.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/acm_certificate_validation) | resource |
| [aws_lb.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb) | resource |
| [aws_lb_listener.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener) | resource |
| [aws_lb_target_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_target_group) | resource |
| [aws_lb_target_group_attachment.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_target_group_attachment) | resource |
| [aws_route53_record.alias](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record) | resource |
| [aws_route53_record.certificate_validation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record) | resource |
| [aws_security_group.lb](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_vpc_security_group_egress_rule.lb_to_targets](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.lb](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_route53_zone.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/route53_zone) | data source |
| [aws_vpc.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/vpc) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_access_logs"></a> [access\_logs](#input\_access\_logs) | Write access logs to this S3 bucket (with an optional key prefix). Off when null. The bucket's policy must allow Elastic Load Balancing to write to it. | <pre>object({<br/>    bucket = string<br/>    prefix = optional(string)<br/>  })</pre> | `null` | no |
| <a name="input_additional_tags"></a> [additional\_tags](#input\_additional\_tags) | Additional tags to apply to all resources created by this module. | `map(string)` | `{}` | no |
| <a name="input_apex_domain"></a> [apex\_domain](#input\_apex\_domain) | Apex domain of the public Route53 hosted zone used for dns\_records and certificate validation. | `string` | `""` | no |
| <a name="input_certificate_alternative_names"></a> [certificate\_alternative\_names](#input\_certificate\_alternative\_names) | Additional domains (SANs) for the created certificate. | `list(string)` | `[]` | no |
| <a name="input_certificate_domain_name"></a> [certificate\_domain\_name](#input\_certificate\_domain\_name) | Primary domain for the created certificate (e.g. app.example.com). | `string` | `""` | no |
| <a name="input_create_certificate"></a> [create\_certificate](#input\_create\_certificate) | ALB only: create a public ACM certificate, DNS-validated in apex\_domain's hosted zone. HTTPS listeners without their own certificate\_arn use it. | `bool` | `false` | no |
| <a name="input_default_ssl_policy"></a> [default\_ssl\_policy](#input\_default\_ssl\_policy) | TLS security policy for HTTPS and TLS listeners that don't set their own ssl\_policy. | `string` | `"ELBSecurityPolicy-TLS13-1-2-2021-06"` | no |
| <a name="input_dns_evaluate_target_health"></a> [dns\_evaluate\_target\_health](#input\_dns\_evaluate\_target\_health) | Have Route53 evaluate the load balancer's target health for the alias records. | `bool` | `false` | no |
| <a name="input_dns_records"></a> [dns\_records](#input\_dns\_records) | FQDNs to create as A-record aliases of the load balancer, in apex\_domain's hosted zone. | `list(string)` | `[]` | no |
| <a name="input_enable_cross_zone_load_balancing"></a> [enable\_cross\_zone\_load\_balancing](#input\_enable\_cross\_zone\_load\_balancing) | NLB only: load-balance across all registered targets in all AZs by default. ALBs always load-balance across zones. Target groups can override this with cross\_zone. | `bool` | `false` | no |
| <a name="input_enable_deletion_protection"></a> [enable\_deletion\_protection](#input\_enable\_deletion\_protection) | Prevent the load balancer from being deleted through the API. | `bool` | `false` | no |
| <a name="input_idle_timeout"></a> [idle\_timeout](#input\_idle\_timeout) | ALB only: seconds a connection may stay idle. | `number` | `60` | no |
| <a name="input_ingress_rules"></a> [ingress\_rules](#input\_ingress\_rules) | Ingress rules for the load balancer's security group. Each rule admits traffic from cidr\_blocks, security\_groups (source security group IDs), or both. Same shape as red-instance's ingress\_rules. | <pre>list(object({<br/>    description     = string<br/>    from_port       = number<br/>    to_port         = number<br/>    protocol        = string<br/>    cidr_blocks     = optional(list(string), [])<br/>    security_groups = optional(list(string), [])<br/>  }))</pre> | `[]` | no |
| <a name="input_internal"></a> [internal](#input\_internal) | Create an internal load balancer instead of an internet-facing one. | `bool` | `false` | no |
| <a name="input_lb_name"></a> [lb\_name](#input\_lb\_name) | Name of the load balancer. Also prefixes target group and security group names. Letters, digits and hyphens; at most 32 characters. | `string` | n/a | yes |
| <a name="input_listeners"></a> [listeners](#input\_listeners) | Listeners, keyed by a short static name. Each either forwards to a target<br/>group (target\_group = its key) or, on an ALB HTTP listener, redirects to<br/>HTTPS (redirect\_to\_https = true). HTTPS and TLS listeners need a<br/>certificate: certificate\_arn, or the module-created certificate (ALB only). | <pre>map(object({<br/>    port              = number<br/>    protocol          = string<br/>    target_group      = optional(string)<br/>    redirect_to_https = optional(bool, false)<br/>    certificate_arn   = optional(string)<br/>    ssl_policy        = optional(string)<br/>  }))</pre> | `{}` | no |
| <a name="input_load_balancer_type"></a> [load\_balancer\_type](#input\_load\_balancer\_type) | Type of load balancer: "network" (NLB) or "application" (ALB). | `string` | n/a | yes |
| <a name="input_project_name"></a> [project\_name](#input\_project\_name) | Project name used for the Project tag. | `string` | n/a | yes |
| <a name="input_subnet_ids"></a> [subnet\_ids](#input\_subnet\_ids) | Subnet IDs for the load balancer, one per Availability Zone it should serve. ALBs require at least two. | `list(string)` | n/a | yes |
| <a name="input_target_cidr_blocks"></a> [target\_cidr\_blocks](#input\_target\_cidr\_blocks) | Destination CIDRs for the security group's egress to targets. Defaults to the VPC's CIDR. Set this when IP targets live outside the VPC (e.g. a peered network). | `list(string)` | `null` | no |
| <a name="input_target_groups"></a> [target\_groups](#input\_target\_groups) | Target groups, keyed by a short static name (used in resource names and<br/>referenced by listeners). Each group may register its own targets, keyed by<br/>a static name, with an optional per-target port override. Omit targets to<br/>attach them outside the module (e.g. from an Auto Scaling group). | <pre>map(object({<br/>    port                 = number<br/>    protocol             = string<br/>    target_type          = optional(string, "instance")<br/>    deregistration_delay = optional(number, 300)<br/>    cross_zone           = optional(bool)<br/>    preserve_client_ip   = optional(bool)<br/>    health_check = optional(object({<br/>      protocol            = optional(string)<br/>      port                = optional(string, "traffic-port")<br/>      path                = optional(string, "/")<br/>      matcher             = optional(string, "200")<br/>      interval            = optional(number, 30)<br/>      timeout             = optional(number)<br/>      healthy_threshold   = optional(number, 3)<br/>      unhealthy_threshold = optional(number, 3)<br/>    }), {})<br/>    targets = optional(map(object({<br/>      id   = string<br/>      port = optional(number)<br/>    })), {})<br/>  }))</pre> | `{}` | no |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | ID of the VPC the load balancer and its target groups live in. | `string` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_certificate_arn"></a> [certificate\_arn](#output\_certificate\_arn) | ARN of the module-created, validated certificate, or null. |
| <a name="output_dns_records"></a> [dns\_records](#output\_dns\_records) | FQDNs of the alias records created for the load balancer. |
| <a name="output_lb_arn"></a> [lb\_arn](#output\_lb\_arn) | ARN of the load balancer. |
| <a name="output_lb_dns_name"></a> [lb\_dns\_name](#output\_lb\_dns\_name) | AWS-assigned DNS name of the load balancer. |
| <a name="output_lb_zone_id"></a> [lb\_zone\_id](#output\_lb\_zone\_id) | Route53 zone ID of the load balancer, for alias records created outside the module. |
| <a name="output_listener_arns"></a> [listener\_arns](#output\_listener\_arns) | Listener ARNs, keyed like var.listeners. |
| <a name="output_security_group_id"></a> [security\_group\_id](#output\_security\_group\_id) | The load balancer's security group. Reference it from targets' ingress rules (e.g. red-instance ingress\_rules[*].security\_groups). |
| <a name="output_target_group_arns"></a> [target\_group\_arns](#output\_target\_group\_arns) | Target group ARNs, keyed like var.target\_groups. Use these to attach targets outside the module. |
<!-- END_TF_DOCS -->
<!-- prettier-ignore-end -->
