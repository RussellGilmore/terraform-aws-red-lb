variable "project_name" {
  type    = string
  default = "red-lb-nlb-example"
}

variable "region" {
  type    = string
  default = "us-east-1"
}

variable "lb_name" {
  type    = string
  default = "red-lb-nlb-example"
}

variable "instance_name" {
  type    = string
  default = "red-lb-nlb-target"
}

provider "aws" {
  region = var.region
}

module "network" {
  source = "git::https://github.com/RussellGilmore/terraform-aws-red-network.git?ref=v3.0.0"

  project_name = var.project_name
  vpc_name     = "${var.project_name}-vpc"
  vpc_cidr     = "10.40.0.0/16"

  subnets = {
    public_a = {
      name              = "${var.project_name}-public-a"
      cidr_block        = "10.40.0.0/24"
      availability_zone = "${var.region}a"
      type              = "public"
    }
    public_b = {
      name              = "${var.project_name}-public-b"
      cidr_block        = "10.40.1.0/24"
      availability_zone = "${var.region}b"
      type              = "public"
    }
  }

  create_nat_gateway = false
}

# A target serving a known page on 8080, reachable only through the NLB.
module "target" {
  source = "git::https://github.com/RussellGilmore/terraform-aws-red-instance.git?ref=v2.5.0"

  project_name  = var.project_name
  instance_name = var.instance_name

  create_vpc = false
  vpc_id     = module.network.vpc_id
  subnet_id  = module.network.subnet_ids["public_a"]

  ingress_rules = [
    {
      description     = "App port from the NLB only"
      from_port       = 8080
      to_port         = 8080
      protocol        = "tcp"
      security_groups = [module.nlb.security_group_id]
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

module "nlb" {
  source = "../../"

  project_name       = var.project_name
  lb_name            = var.lb_name
  load_balancer_type = "network"
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
  ]

  target_groups = {
    web = {
      port                 = 8080
      protocol             = "TCP"
      deregistration_delay = 30
      # The target is in one AZ; NLB nodes in the other AZ must still reach it.
      cross_zone = true
      health_check = {
        interval = 10
      }
      targets = {
        app = { id = module.target.instance_id }
      }
    }
  }

  listeners = {
    http = { port = 80, protocol = "TCP", target_group = "web" }
  }

  additional_tags = {
    Environment = "example"
  }
}

output "lb_dns_name" {
  description = "DNS name of the NLB."
  value       = module.nlb.lb_dns_name
}

output "security_group_id" {
  description = "The NLB's security group."
  value       = module.nlb.security_group_id
}

output "target_group_arns" {
  description = "Target group ARNs."
  value       = module.nlb.target_group_arns
}
