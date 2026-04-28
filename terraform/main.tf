terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    github = {
      source  = "integrations/github"
      version = "~> 6.0"
    }
  }
}

provider "google" {
  project = var.gcp_project_id
}

provider "github" {
  owner = var.github_org
}

data "google_client_config" "current" {}

locals {
  repo_name = var.repo_name != "" ? var.repo_name : basename(path.root)
}

module "railway" {
  count  = var.enable_railway ? 1 : 0
  source = "./modules/railway-services"

  environment_name = local.repo_name
  enable_postgresql = true
  enable_n8n        = var.enable_n8n
  enable_webhooks   = true
  gcp_project_id    = var.gcp_project_id
}

module "cloudflare" {
  count  = var.enable_cloudflare ? 1 : 0
  source = "./modules/cloudflare-gateway"

  repo_name             = local.repo_name
  cloudflare_account_id = var.cloudflare_account_id
  cloudflare_zone_id    = var.cloudflare_zone_id
  domain                = var.cloudflare_domain
  gcp_project_id        = var.gcp_project_id
  backend_url           = var.enable_railway ? module.railway[0].webhook_handler_url : ""
}
