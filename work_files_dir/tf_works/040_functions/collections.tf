locals {
  services_a = ["api", "web"]
  services_b = ["database", "cache"]
  all_services = concat(local.services_a, local.services_b)

  nested_cidrs = [["10.0.1.0/24", "10.0.2.0/24"], ["10.0.3.0/24"]]
  flat_cidrs   = flatten(local.nested_cidrs)

  config = {
    site    = "robochef.co"
    owner   = "saravanans"
    env     = "prod"
    version = "2.1"
  }

  defaults = {
    site    = "example.com"
    owner   = "unknown"
    region  = "us-east-1"
  }

  merged_config = merge(local.defaults, local.config)
}

resource "local_file" "collection_demo" {
  filename = "/tmp/robochef-collections.txt"
  content  = <<-EOT
    # concat
    all_services=${join(", ", local.all_services)}
    service_count=${length(local.all_services)}

    # flatten
    all_cidrs=${join(", ", local.flat_cidrs)}

    # keys and values
    config_keys=${join(", ", keys(local.config))}

    # lookup with default
    site=${lookup(local.config, "site", "unknown")}
    missing=${lookup(local.config, "missing", "default-value")}

    # merge (local.config overrides local.defaults)
    merged_site=${local.merged_config["site"]}
    merged_region=${local.merged_config["region"]}

    # toset deduplication
    unique_tags=${join(", ", toset(["api", "web", "api", "db", "web"]))}

    # contains
    has_api=${contains(local.all_services, "api")}
    has_queue=${contains(local.all_services, "queue")}

    # element
    first_service=${element(local.all_services, 0)}
    second_service=${element(local.all_services, 1)}

    # slice
    first_two=${join(", ", slice(local.all_services, 0, 2))}
  EOT
}
