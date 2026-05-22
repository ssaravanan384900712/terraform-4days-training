# main.tf

# ── Rendered configs live in locals ────────────────────────────────────────
locals {
  robochef_config = templatefile("${path.module}/templates/site.conf.tpl", {
    owner        = "saravanans"
    domain       = "robochef.co"
    port         = 443
    app_name     = "robochef"
    app_port     = 3000
    generated_at = timestamp()
    features     = ["auth", "analytics", "dark-mode"]
  })

  chillbot_config = templatefile("${path.module}/templates/site.conf.tpl", {
    owner        = "saravanans"
    domain       = "chillbotindia.com"
    port         = 80
    app_name     = "chillbot"
    app_port     = 8080
    generated_at = timestamp()
    features     = ["chat", "notifications"]
  })
}

# ── Write the rendered configs to /tmp so you can cat them ─────────────────
resource "local_file" "robochef_nginx" {
  filename = "/tmp/robochef-nginx.conf"
  content  = local.robochef_config
}

resource "local_file" "chillbot_nginx" {
  filename = "/tmp/chillbot-nginx.conf"
  content  = local.chillbot_config
}

# ── file() vs templatefile() side-by-side demo ─────────────────────────────
locals {
  # file() — reads raw bytes, returns them unchanged
  raw_template = file("${path.module}/templates/site.conf.tpl")

  # templatefile() — reads and substitutes
  rendered = templatefile("${path.module}/templates/site.conf.tpl", {
    owner        = "demo"
    domain       = "example.com"
    port         = 80
    app_name     = "demo-app"
    app_port     = 3000
    generated_at = "2026-05-21"
    features     = ["feature-x"]
  })
}

output "raw_vs_rendered" {
  value = {
    raw      = local.raw_template   # still has ${domain}, ${port}, etc.
    rendered = local.rendered       # substituted values
  }
}

# ── Conditional directives demo ─────────────────────────────────────────────
locals {
  robochef_ssl_config = templatefile("${path.module}/templates/site-advanced.conf.tpl", {
    domain   = "robochef.co"
    port     = 443
    app_port = 3000
  })

  chillbot_plain_config = templatefile("${path.module}/templates/site-advanced.conf.tpl", {
    domain   = "chillbotindia.com"
    port     = 80
    app_port = 8080
  })
}
