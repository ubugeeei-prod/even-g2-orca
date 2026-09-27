terraform {
  required_version = ">= 1.10, < 2.0"
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "= 5.26.0"
    }
  }
}

# Authentication is read from CLOUDFLARE_API_TOKEN, never from source or tfvars.
provider "cloudflare" {}
