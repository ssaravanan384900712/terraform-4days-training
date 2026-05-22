terraform {
  required_providers {
    vault = { source = "hashicorp/vault", version = "~> 3.0" }
    local = { source = "hashicorp/local", version = "~> 2.0" }
  }
}

provider "vault" {
  address = "http://127.0.0.1:8200"
  token   = "environment"  # in prod: use VAULT_TOKEN env var instead
}
