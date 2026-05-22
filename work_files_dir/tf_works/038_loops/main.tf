terraform {
  required_providers {
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

# ── Part 1a: for_each with a map of objects ───────────────────────────────────

variable "sites" {
  description = "Sites managed on robochef infrastructure"
  type = map(object({
    domain = string
    owner  = string
  }))
  default = {
    robochef = {
      domain = "robochef.co"
      owner  = "saravanans"
    }
    chillbot = {
      domain = "chillbotindia.com"
      owner  = "saravanans"
    }
    personal = {
      domain = "saravanans.dev"
      owner  = "saravanans"
    }
  }
}

resource "local_file" "site_config" {
  for_each = var.sites

  filename = "/tmp/${each.key}-config.txt"
  content  = "domain=${each.value.domain}\nowner=${each.value.owner}\nmanaged_by=terraform\n"
}

output "site_files" {
  value = { for k, v in local_file.site_config : k => v.filename }
}

# ── Part 1b: for_each with random_string ──────────────────────────────────────

resource "random_string" "site_token" {
  for_each = var.sites

  length  = 24
  special = false
  upper   = true
}

output "site_tokens" {
  value     = { for k, v in random_string.site_token : k => v.result }
  sensitive = true
}

# ── Part 2: for expressions ───────────────────────────────────────────────────

variable "usernames" {
  description = "robochef platform users"
  type        = list(string)
  default     = ["saravanans", "robochef_admin", "chillbot_user", "guest"]
}

locals {
  # List: uppercase every username
  upper_users = [for u in var.usernames : upper(u)]

  # List with filter: only usernames longer than 10 characters
  filtered_users = [for u in var.usernames : u if length(u) > 10]

  # Map: username => its character length
  user_length_map = { for u in var.usernames : u => length(u) }

  # Map: username => generated email address
  email_map = { for u in var.usernames : u => "${u}@robochef.co" }

  # Map from map: site => uppercase domain
  upper_domains = { for k, v in var.sites : k => upper(v.domain) }

  # List: only site keys where owner is "saravanans"
  owned_sites = [for k, v in var.sites : k if v.owner == "saravanans"]
}

output "upper_users"    { value = local.upper_users }
output "filtered_users" { value = local.filtered_users }
output "user_length_map" { value = local.user_length_map }
output "email_map"       { value = local.email_map }
output "upper_domains"   { value = local.upper_domains }
output "owned_sites"     { value = local.owned_sites }

# ── Part 3: dynamic block pattern (simulation + real syntax) ──────────────────

variable "ports" {
  description = "Ports to allow through robochef firewall"
  type        = list(number)
  default     = [80, 443, 8080]
}

variable "environments_fw" {
  description = "Environments to generate firewall rules for"
  type        = list(string)
  default     = ["dev", "staging", "prod"]
}

locals {
  # Simulate what dynamic ingress blocks would allow
  port_rules = [for p in var.ports : "ALLOW TCP ${p} FROM 0.0.0.0/0"]

  # Cross product: environment × port
  env_port_rules = flatten([
    for env in var.environments_fw : [
      for p in var.ports : "ENV=${env} ALLOW TCP ${p}"
    ]
  ])
}

resource "local_file" "firewall_rules" {
  filename = "/tmp/robochef-firewall.txt"
  content  = join("\n", local.port_rules)
}

resource "local_file" "env_firewall_rules" {
  filename = "/tmp/robochef-env-firewall.txt"
  content  = join("\n", local.env_port_rules)
}

output "firewall_file"     { value = local_file.firewall_rules.filename }
output "env_firewall_file" { value = local_file.env_firewall_rules.filename }
output "port_rules"        { value = local.port_rules }
output "env_port_rules"    { value = local.env_port_rules }

# ── Part 5: combined example ──────────────────────────────────────────────────

variable "teams" {
  description = "robochef engineering teams"
  default = {
    backend  = { lead = "saravanans", size = 4 }
    frontend = { lead = "saravanans", size = 3 }
    devops   = { lead = "saravanans", size = 2 }
  }
}

locals {
  # for expression: build member list per team
  team_emails = {
    for team, info in var.teams :
    team => "${info.lead}+${team}@robochef.co"
  }

  # for expression: teams larger than 3 people
  large_teams = [for team, info in var.teams : team if info.size > 3]

  # for expression: total headcount
  total_headcount = sum([for team, info in var.teams : info.size])
}

# for_each: one config file per team
resource "local_file" "team_config" {
  for_each = var.teams

  filename = "/tmp/robochef-team-${each.key}.txt"
  content  = <<-CONFIG
    team=${each.key}
    lead=${each.value.lead}
    size=${each.value.size}
    email=${local.team_emails[each.key]}
  CONFIG
}

# for_each: one API token per team
resource "random_string" "team_token" {
  for_each = var.teams

  length  = 32
  special = false
}

output "team_config_files" {
  value = { for k, v in local_file.team_config : k => v.filename }
}

output "team_emails"      { value = local.team_emails }
output "large_teams"      { value = local.large_teams }
output "total_headcount"  { value = local.total_headcount }

output "team_tokens" {
  value     = { for k, v in random_string.team_token : k => v.result }
  sensitive = true
}
