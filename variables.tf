####################################################################################################
# Required Variables
variable "project_name" {
  description = "Project name used for the Project tag."
  type        = string
}

variable "lb_name" {
  description = "Name of the load balancer. Also prefixes target group and security group names. Letters, digits and hyphens; at most 32 characters."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9](?:[A-Za-z0-9-]{0,30}[A-Za-z0-9])?$", var.lb_name))
    error_message = "lb_name must be 1-32 characters of letters, digits and hyphens, and must not start or end with a hyphen."
  }
}

variable "load_balancer_type" {
  description = "Type of load balancer: \"network\" (NLB) or \"application\" (ALB)."
  type        = string

  validation {
    condition     = contains(["network", "application"], var.load_balancer_type)
    error_message = "load_balancer_type must be \"network\" or \"application\"."
  }
}

variable "vpc_id" {
  description = "ID of the VPC the load balancer and its target groups live in."
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs for the load balancer, one per Availability Zone it should serve. ALBs require at least two."
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= (var.load_balancer_type == "application" ? 2 : 1)
    error_message = "subnet_ids needs at least one subnet, and at least two for an application load balancer."
  }
}

####################################################################################################
# Tagging
variable "additional_tags" {
  description = "Additional tags to apply to all resources created by this module."
  type        = map(string)
  default     = {}
}

####################################################################################################
# Load Balancer
variable "internal" {
  description = "Create an internal load balancer instead of an internet-facing one."
  type        = bool
  default     = false
}

variable "enable_deletion_protection" {
  description = "Prevent the load balancer from being deleted through the API."
  type        = bool
  default     = false
}

variable "enable_cross_zone_load_balancing" {
  description = "NLB only: load-balance across all registered targets in all AZs by default. ALBs always load-balance across zones. Target groups can override this with cross_zone."
  type        = bool
  default     = false
}

variable "idle_timeout" {
  description = "ALB only: seconds a connection may stay idle."
  type        = number
  default     = 60
}

variable "default_ssl_policy" {
  description = "TLS security policy for HTTPS and TLS listeners that don't set their own ssl_policy."
  type        = string
  default     = "ELBSecurityPolicy-TLS13-1-2-2021-06"
}

variable "access_logs" {
  description = "Write access logs to this S3 bucket (with an optional key prefix). Off when null. The bucket's policy must allow Elastic Load Balancing to write to it."
  type = object({
    bucket = string
    prefix = optional(string)
  })
  default = null
}

####################################################################################################
# Security Group
variable "ingress_rules" {
  description = "Ingress rules for the load balancer's security group. Each rule admits traffic from cidr_blocks, security_groups (source security group IDs), or both."
  type = list(object({
    description     = string
    from_port       = number
    to_port         = number
    protocol        = string
    cidr_blocks     = optional(list(string), [])
    security_groups = optional(list(string), [])
  }))
  default = []

  validation {
    condition = alltrue([
      for r in var.ingress_rules : length(r.cidr_blocks) + length(r.security_groups) > 0
    ])
    error_message = "Each ingress rule must set at least one source: cidr_blocks and/or security_groups."
  }
}

variable "target_cidr_blocks" {
  description = "Destination CIDRs for the security group's egress to targets. Defaults to the VPC's CIDR. Set this when IP targets live outside the VPC (e.g. a peered network)."
  type        = list(string)
  default     = null
}

####################################################################################################
# Target Groups
variable "target_groups" {
  description = <<-EOT
    Target groups, keyed by a short static name (used in resource names and
    referenced by listeners). Each group may register its own targets, keyed by
    a static name, with an optional per-target port override. Omit targets to
    attach them outside the module (e.g. from an Auto Scaling group).
  EOT
  type = map(object({
    port                 = number
    protocol             = string
    target_type          = optional(string, "instance")
    deregistration_delay = optional(number, 300)
    cross_zone           = optional(bool)
    preserve_client_ip   = optional(bool)
    health_check = optional(object({
      protocol            = optional(string)
      port                = optional(string, "traffic-port")
      path                = optional(string, "/")
      matcher             = optional(string, "200")
      interval            = optional(number, 30)
      timeout             = optional(number)
      healthy_threshold   = optional(number, 3)
      unhealthy_threshold = optional(number, 3)
    }), {})
    targets = optional(map(object({
      id   = string
      port = optional(number)
    })), {})
  }))
  default = {}

  validation {
    condition = alltrue([
      for k, tg in var.target_groups : contains(
        var.load_balancer_type == "application" ? ["HTTP", "HTTPS"] : ["TCP", "UDP", "TCP_UDP", "TLS"],
        tg.protocol
      )
    ])
    error_message = "Target group protocol must be HTTP or HTTPS for an ALB, or TCP, UDP, TCP_UDP or TLS for an NLB."
  }

  validation {
    condition     = alltrue([for k, tg in var.target_groups : contains(["instance", "ip"], tg.target_type)])
    error_message = "target_type must be \"instance\" or \"ip\"."
  }

  validation {
    condition     = alltrue([for k, tg in var.target_groups : length("${var.lb_name}-${k}") <= 25])
    error_message = "Target group names are \"<lb_name>-<key>-<6-character hash>\" and AWS limits them to 32 characters, so \"<lb_name>-<key>\" must be at most 25. Shorten lb_name or the key."
  }

  validation {
    condition = alltrue([
      for k, tg in var.target_groups :
      tg.health_check.port == "traffic-port" || can(tonumber(tg.health_check.port))
    ])
    error_message = "health_check.port must be \"traffic-port\" or a port number."
  }

  validation {
    condition = var.load_balancer_type == "network" || alltrue([
      for k, tg in var.target_groups : tg.preserve_client_ip == null
    ])
    error_message = "preserve_client_ip applies to NLB target groups only."
  }
}

####################################################################################################
# Listeners
variable "listeners" {
  description = <<-EOT
    Listeners, keyed by a short static name. Each either forwards to a target
    group (target_group = its key) or, on an ALB HTTP listener, redirects to
    HTTPS (redirect_to_https = true). HTTPS and TLS listeners need a
    certificate: certificate_arn, or the module-created certificate (ALB only).
  EOT
  type = map(object({
    port              = number
    protocol          = string
    target_group      = optional(string)
    redirect_to_https = optional(bool, false)
    certificate_arn   = optional(string)
    ssl_policy        = optional(string)
  }))
  default = {}

  validation {
    condition = alltrue([
      for k, l in var.listeners : contains(
        var.load_balancer_type == "application" ? ["HTTP", "HTTPS"] : ["TCP", "UDP", "TCP_UDP", "TLS"],
        l.protocol
      )
    ])
    error_message = "Listener protocol must be HTTP or HTTPS for an ALB, or TCP, UDP, TCP_UDP or TLS for an NLB."
  }

  validation {
    condition = alltrue([
      for k, l in var.listeners : (l.target_group != null) != l.redirect_to_https
    ])
    error_message = "Each listener needs exactly one action: target_group, or redirect_to_https = true."
  }

  validation {
    condition = alltrue([
      for k, l in var.listeners : l.target_group == null || contains(keys(var.target_groups), coalesce(l.target_group, "-"))
    ])
    error_message = "A listener's target_group must be a key in target_groups."
  }

  validation {
    condition = alltrue([
      for k, l in var.listeners :
      !l.redirect_to_https || (var.load_balancer_type == "application" && l.protocol == "HTTP")
    ])
    error_message = "redirect_to_https is only valid on ALB HTTP listeners."
  }

  validation {
    condition = alltrue([
      for k, l in var.listeners :
      !contains(["HTTPS", "TLS"], l.protocol) || l.certificate_arn != null ||
      (var.create_certificate && var.load_balancer_type == "application")
    ])
    error_message = "HTTPS and TLS listeners need certificate_arn, or create_certificate = true on an ALB."
  }
}

####################################################################################################
# Certificate (ALB only)
variable "create_certificate" {
  description = "ALB only: create a public ACM certificate, DNS-validated in apex_domain's hosted zone. HTTPS listeners without their own certificate_arn use it."
  type        = bool
  default     = false

  validation {
    condition     = !var.create_certificate || var.load_balancer_type == "application"
    error_message = "create_certificate is only supported on application load balancers."
  }
}

variable "certificate_domain_name" {
  description = "Primary domain for the created certificate (e.g. app.example.com)."
  type        = string
  default     = ""

  validation {
    condition     = !var.create_certificate || var.certificate_domain_name != ""
    error_message = "certificate_domain_name is required when create_certificate is true."
  }
}

variable "certificate_alternative_names" {
  description = "Additional domains (SANs) for the created certificate."
  type        = list(string)
  default     = []
}

####################################################################################################
# Public DNS
variable "apex_domain" {
  description = "Apex domain of the public Route53 hosted zone used for dns_records and certificate validation."
  type        = string
  default     = ""

  validation {
    condition     = var.apex_domain != "" || (!var.create_certificate && length(var.dns_records) == 0)
    error_message = "apex_domain is required when create_certificate is true or dns_records is set."
  }
}

variable "dns_records" {
  description = "FQDNs to create as A-record aliases of the load balancer, in apex_domain's hosted zone."
  type        = list(string)
  default     = []
}

variable "dns_evaluate_target_health" {
  description = "Have Route53 evaluate the load balancer's target health for the alias records."
  type        = bool
  default     = false
}
