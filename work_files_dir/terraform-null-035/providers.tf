# providers.tf
terraform {
  required_version = ">= 1.4"

  required_providers {
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
  }
}

# No provider configuration blocks are needed.
# null and local providers work without any credentials.
