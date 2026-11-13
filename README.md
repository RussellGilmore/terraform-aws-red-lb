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



### ALB with a managed certificate and HTTP-to-HTTPS redirect



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
