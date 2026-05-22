locals {
  vpc_cidr = "10.0.0.0/16"

  subnets = {
    public_1  = cidrsubnet(local.vpc_cidr, 8, 1)
    public_2  = cidrsubnet(local.vpc_cidr, 8, 2)
    private_1 = cidrsubnet(local.vpc_cidr, 8, 10)
    private_2 = cidrsubnet(local.vpc_cidr, 8, 11)
    db_1      = cidrsubnet(local.vpc_cidr, 8, 20)
  }

  gateway_ip   = cidrhost(local.subnets["public_1"], 1)
  lb_ip        = cidrhost(local.subnets["public_1"], 5)
  app_ip       = cidrhost(local.subnets["private_1"], 10)
  db_ip        = cidrhost(local.subnets["db_1"], 10)
}

resource "local_file" "network_plan" {
  filename = "/tmp/robochef-network.txt"
  content  = <<-EOT
    site=robochef.co
    owner=saravanans

    # VPC
    vpc_cidr=${local.vpc_cidr}
    vpc_netmask=${cidrnetmask(local.vpc_cidr)}

    # Subnets (auto-calculated from VPC CIDR)
    public_1=${local.subnets["public_1"]}
    public_2=${local.subnets["public_2"]}
    private_1=${local.subnets["private_1"]}
    private_2=${local.subnets["private_2"]}
    db_1=${local.subnets["db_1"]}

    # Host addresses
    gateway=${local.gateway_ip}
    load_balancer=${local.lb_ip}
    app_server=${local.app_ip}
    db_server=${local.db_ip}
    subnet_mask=${cidrnetmask(local.subnets["public_1"])}
  EOT
}
