locals {
  base_port    = 8080
  replica_raw  = 2.7
  memory_mb    = -512
}

resource "local_file" "numeric_demo" {
  filename = "/tmp/robochef-numeric.txt"
  content  = <<-EOT
    site=robochef.co
    owner=saravanans

    # abs: make negative memory positive
    memory_mb=${abs(local.memory_mb)}

    # ceil: always round replicas UP
    replicas=${ceil(local.replica_raw)}

    # floor: conservative floor estimate
    replicas_floor=${floor(local.replica_raw)}

    # max/min: clamp port to valid range
    port=${max(local.base_port, 1024)}
    max_port=${min(local.base_port, 65535)}

    # pow: 2^10 = 1024 connections
    max_connections=${pow(2, 10)}
  EOT
}
