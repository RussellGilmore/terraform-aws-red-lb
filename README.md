# terraform-aws-red-lb

Terraform module for an AWS Network Load Balancer (NLB) or Application Load
Balancer (ALB), with its own security group, target groups, listeners, and
optional public DNS and ACM certificate.

## Features

-   One module for both load balancer types (`load_balancer_type`)
-   Dedicated security group: ingress from CIDRs and/or source security groups
    (same `ingress_rules` shape as red-instance); egress derived automatically
    from the target groups' ports and health checks
-   Target groups with optional in-module target attachments, or ARNs output
    for attaching targets elsewhere (e.g. an Auto Scaling group)
-   Listeners that forward to a target group or, on ALB HTTP listeners,
    redirect to HTTPS
-   TLS 1.3 security policy by default on HTTPS/TLS listeners
-   ALB hardening: invalid header fields are dropped
-   Optional public ACM certificate for ALBs, DNS-validated in Route53
-   Optional Route53 alias records
-   Optional access logs to an existing S3 bucket (off by default)

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

-   **Names:** target groups are named `<lb_name>-<key>`, and AWS limits load
    balancer and target group names to 32 characters. Validation checks this
    at plan time.
-   **Client IPs:** NLB instance targets preserve client IPs by default. Target
    security groups should reference the load balancer's security group
    (`security_group_id`) rather than allowing the internet.
-   **Cross-zone:** NLBs default to in-zone routing. Set `cross_zone = true` on a
    target group whose targets don't cover every AZ the NLB is in.
-   **Egress:** the security group only allows traffic to the target groups'
    ports in the VPC CIDR. Set `target_cidr_blocks` for IP targets elsewhere.

<!-- BEGIN_TF_DOCS -->
<!-- END_TF_DOCS -->
