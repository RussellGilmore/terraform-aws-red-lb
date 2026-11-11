variable "project_name" {
  type    = string
  default = "red-lb-alb-example"
}

variable "region" {
  type    = string
  default = "us-east-1"
}

variable "lb_name" {
  type    = string
  default = "red-lb-alb-example"
}

variable "instance_name" {
  type    = string
  default = "red-lb-alb-target"
}

provider "aws" {
  region = var.region
}

module "network" {
  source = "git::https://github.com/RussellGilmore/terraform-aws-red-network.git?ref=v3.0.0"

  project_name = var.project_name
  vpc_name     = "${var.project_name}-vpc"
  vpc_cidr     = "10.41.0.0/16"

  # ALBs require subnets in at least two AZs.
  subnets = {
    public_a = {
      name              = "${var.project_name}-public-a"
      cidr_block        = "10.41.0.0/24"
      availability_zone = "${var.region}a"
      type              = "public"
    }
    public_b = {
      name              = "${var.project_name}-public-b"
      cidr_block        = "10.41.1.0/24"
      availability_zone = "${var.region}b"
      type              = "public"
    }
  }

  create_nat_gateway = false
}

# A target serving a known page on 8080, reachable only through the ALB.
module "target" {
  source = "git::https://github.com/RussellGilmore/terraform-aws-red-instance.git?ref=v2.5.0"

  project_name  = var.project_name
  instance_name = var.instance_name

  create_vpc = false
  vpc_id     = module.network.vpc_id
  subnet_id  = module.network.subnet_ids["public_a"]

  ingress_rules = [
    {
      description     = "App port from the ALB only"
      from_port       = 8080
      to_port         = 8080
      protocol        = "tcp"
      security_groups = [module.alb.security_group_id]
    },
  ]

  user_data = <<-EOF
    #cloud-config
    write_files:
      - path: /srv/red-lb/index.html
        content: |
          red-lb-ok
    runcmd:
      - [ sh, -c, "cd /srv/red-lb && nohup python3 -m http.server 8080 >/var/log/red-lb-http.log 2>&1 &" ]
  EOF
}

module "alb" {
  source = "../../"

  project_name       = var.project_name
  lb_name            = var.lb_name
  load_balancer_type = "application"
  vpc_id             = module.network.vpc_id
  subnet_ids         = [module.network.subnet_ids["public_a"], module.network.subnet_ids["public_b"]]

  ingress_rules = [
    {
      description = "HTTP from anywhere"
      from_port   = 80
      to_port     = 80
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    },
    {
      description = "Redirect test listener from anywhere"
      from_port   = 8081
      to_port     = 8081
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    },
  ]

  target_groups = {
    web = {
      port                 = 8080
      protocol             = "HTTP"
      deregistration_delay = 30
      health_check = {
        path     = "/"
        matcher  = "200"
        interval = 10
      }
      targets = {
        app = { id = module.target.instance_id }
      }
    }
  }

  listeners = {
    # Forwards to the target group.
    http = { port = 80, protocol = "HTTP", target_group = "web" }

    # Exercises redirect_to_https. A real deployment puts this on port 80
    # alongside an HTTPS listener (see the README); a separate port lets the
    # test cover both actions without a certificate.
    redirect = { port = 8081, protocol = "HTTP", redirect_to_https = true }
  }

  additional_tags = {
    Environment = "example"
  }
}

output "lb_dns_name" {
  description = "DNS name of the ALB."
  value       = module.alb.lb_dns_name
}

output "security_group_id" {
  description = "The ALB's security group."
  value       = module.alb.security_group_id
}

output "target_group_arns" {
  description = "Target group ARNs."
  value       = module.alb.target_group_arns
}
