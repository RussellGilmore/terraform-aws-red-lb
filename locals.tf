locals {
  tags = merge(
    {
      Orchestrator = "Terraform"
      Artifact     = "Red-LB"
      Project      = var.project_name
    },
    var.additional_tags
  )

  is_alb = var.load_balancer_type == "application"
  is_nlb = var.load_balancer_type == "network"

  # Security group protocol(s) each target group protocol needs.
  protocol_map = {
    TCP     = ["tcp"]
    TLS     = ["tcp"]
    UDP     = ["udp"]
    TCP_UDP = ["tcp", "udp"]
    HTTP    = ["tcp"]
    HTTPS   = ["tcp"]
  }

  # Health check protocol per target group: as given, else the target
  # group's protocol on ALBs and TCP on NLBs (NLB UDP/TLS groups check over TCP).
  health_protocols = {
    for k, tg in var.target_groups :
    k => coalesce(tg.health_check.protocol, local.is_alb ? tg.protocol : "TCP")
  }

  # Every port traffic is forwarded to, per target group (the group port plus
  # any per-target overrides).
  target_ports = {
    for k, tg in var.target_groups :
    k => distinct(concat([tg.port], [for t in values(tg.targets) : coalesce(t.port, tg.port)]))
  }

  # Health-check port(s) per target group. Both branches are list(number),
  # so the conditional is type-consistent.
  health_ports = {
    for k, tg in var.target_groups :
    k => tg.health_check.port == "traffic-port" ? local.target_ports[k] : [tonumber(tg.health_check.port)]
  }

  # Egress the load balancer needs: forwarding on each target port, plus TCP
  # on the health-check port(s). Keyed by protocol and port, so duplicates
  # across target groups collapse.
  egress_ports = merge(concat(
    [
      for k, tg in var.target_groups : {
        for pair in setproduct(local.protocol_map[tg.protocol], local.target_ports[k]) :
        "${pair[0]}-${pair[1]}" => { protocol = pair[0], port = pair[1] }
      }
    ],
    [
      for k, tg in var.target_groups : {
        for p in local.health_ports[k] :
        "tcp-${p}" => { protocol = "tcp", port = p }
      }
    ]
  )...)

  target_cidr_blocks = coalesce(var.target_cidr_blocks, [data.aws_vpc.this.cidr_block])

  egress_rules = merge([
    for key, e in local.egress_ports : {
      for i, cidr in local.target_cidr_blocks :
      "${key}-${i}" => merge(e, { cidr = cidr })
    }
  ]...)

  # One security group rule per source. Index-based keys keep for_each valid
  # when a source is only known at apply time.
  ingress_rules = merge([
    for i, r in var.ingress_rules : merge(
      {
        for j, cidr in r.cidr_blocks :
        "${i}-cidr-${j}" => merge(r, { cidr = cidr, source_sg = null })
      },
      {
        for j, sg in r.security_groups :
        "${i}-sg-${j}" => merge(r, { cidr = null, source_sg = sg })
      }
    )
  ]...)

  # Flattened target attachments, keyed "<target_group>.<target>".
  target_attachments = merge([
    for tg_key, tg in var.target_groups : {
      for t_key, t in tg.targets :
      "${tg_key}.${t_key}" => {
        tg_key = tg_key
        id     = t.id
        port   = coalesce(t.port, tg.port)
      }
    }
  ]...)

  lookup_zone = var.create_certificate || length(var.dns_records) > 0

  # Target group names carry a short hash of the attributes AWS cannot change
  # in place. Changing one changes the name, so the replacement is created
  # before the old group is destroyed (see target_groups.tf).
  target_group_names = {
    for k, tg in var.target_groups :
    k => "${var.lb_name}-${k}-${substr(sha1("${tg.port}|${tg.protocol}|${tg.target_type}|${var.vpc_id}"), 0, 6)}"
  }
}
