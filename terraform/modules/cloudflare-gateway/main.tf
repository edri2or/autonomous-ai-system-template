terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

variable "repo_name"             { type = string }
variable "cloudflare_account_id" { type = string }
variable "cloudflare_zone_id"    { type = string }
variable "domain"                { type = string }
variable "gcp_project_id"        { type = string }
variable "backend_url"           { type = string; default = "" }
variable "github_webhook_secret" { type = string; default = "" }

resource "cloudflare_workers_script" "webhook_gateway" {
  name       = "webhook-gateway-${var.repo_name}"
  account_id = var.cloudflare_account_id
  content    = file("${path.module}/webhook-gateway.js")

  plain_text_binding {
    name = "WEBHOOK_SECRET"
    text = var.github_webhook_secret
  }

  plain_text_binding {
    name = "BACKEND_URL"
    text = var.backend_url
  }
}

resource "cloudflare_workers_route" "webhook" {
  zone_id     = var.cloudflare_zone_id
  pattern     = "webhooks.${var.domain}/*"
  script_name = cloudflare_workers_script.webhook_gateway.name
}

resource "google_secret_manager_secret" "cloudflare_account_id" {
  project   = var.gcp_project_id
  secret_id = "cloudflare-account-id"

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "cloudflare_account_id" {
  secret      = google_secret_manager_secret.cloudflare_account_id.id
  secret_data = var.cloudflare_account_id
}

output "cloudflare_worker_url" {
  value = "https://webhooks.${var.domain}"
}
