terraform {
  required_providers {
    railway = {
      source  = "terraform-community-providers/railway"
      version = "~> 0.6"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

variable "environment_name"   { type = string }
variable "enable_postgresql"  { type = bool; default = true }
variable "enable_n8n"         { type = bool; default = false }
variable "enable_webhooks"    { type = bool; default = true }
variable "gcp_project_id"     { type = string }
variable "railway_project_id" { type = string; default = "" }
variable "project_domain"     { type = string; default = "" }
variable "n8n_subdomain"      { type = string; default = "n8n" }

resource "random_password" "webhook_secret" {
  length  = 32
  special = false
}

resource "railway_environment" "main" {
  name       = var.environment_name
  project_id = var.railway_project_id
}

# PostgreSQL — Railway native service.
# Automatically injects DATABASE_URL reference variable into other services.
resource "railway_service" "postgres" {
  count      = var.enable_postgresql ? 1 : 0
  name       = "postgres"
  project_id = var.railway_project_id

  source_image = "postgres:15"
}

resource "railway_variable" "postgres_password" {
  count          = var.enable_postgresql ? 1 : 0
  name           = "POSTGRES_PASSWORD"
  value          = random_password.webhook_secret.result
  service_id     = railway_service.postgres[0].id
  environment_id = railway_environment.main.id
}

# N8N — self-hosted workflow engine.
#
# Non-sensitive env vars are set here.
# Sensitive vars (N8N_ENCRYPTION_KEY, N8N_OWNER_PASSWORD) are injected
# post-deploy by deploy-n8n.yml workflow, which reads from GCP Secret Manager.
#
# DATABASE_URL uses Railway's reference variable syntax (${{Postgres.DATABASE_URL}})
# — Railway resolves it automatically to the Postgres service's connection string.
# This is the proven pattern from project-life-130 (Stage 2 complete, state.json "completed").
#
# N8N_BASIC_AUTH_* vars are set for backward compatibility only.
# N8N v1.0+ uses owner/setup API for the first admin account (ADR 0020).
resource "railway_service" "n8n" {
  count      = var.enable_n8n ? 1 : 0
  name       = "n8n"
  project_id = var.railway_project_id

  source_image = "n8nio/n8n:latest"

  depends_on = [railway_service.postgres]
}

resource "railway_variable" "n8n_host" {
  count          = var.enable_n8n ? 1 : 0
  name           = "N8N_HOST"
  value          = "0.0.0.0"
  service_id     = railway_service.n8n[0].id
  environment_id = railway_environment.main.id
}

resource "railway_variable" "n8n_port" {
  count          = var.enable_n8n ? 1 : 0
  name           = "N8N_PORT"
  value          = "5678"
  service_id     = railway_service.n8n[0].id
  environment_id = railway_environment.main.id
}

resource "railway_variable" "n8n_protocol" {
  count          = var.enable_n8n ? 1 : 0
  name           = "N8N_PROTOCOL"
  value          = "https"
  service_id     = railway_service.n8n[0].id
  environment_id = railway_environment.main.id
}

resource "railway_variable" "n8n_webhook_url" {
  count          = var.enable_n8n && var.project_domain != "" ? 1 : 0
  name           = "WEBHOOK_URL"
  value          = "https://${var.n8n_subdomain}.${var.project_domain}/"
  service_id     = railway_service.n8n[0].id
  environment_id = railway_environment.main.id
}

resource "railway_variable" "n8n_editor_base_url" {
  count          = var.enable_n8n && var.project_domain != "" ? 1 : 0
  name           = "N8N_EDITOR_BASE_URL"
  value          = "https://${var.n8n_subdomain}.${var.project_domain}"
  service_id     = railway_service.n8n[0].id
  environment_id = railway_environment.main.id
}

resource "railway_variable" "n8n_db_type" {
  count          = var.enable_n8n ? 1 : 0
  name           = "DB_TYPE"
  value          = "postgresdb"
  service_id     = railway_service.n8n[0].id
  environment_id = railway_environment.main.id
}

# Railway reference variable — resolved automatically by Railway at runtime.
# Equivalent to DATABASE_URL from the Postgres service's internal connection string.
resource "railway_variable" "n8n_database_url" {
  count          = var.enable_n8n ? 1 : 0
  name           = "DATABASE_URL"
  value          = "${{Postgres.DATABASE_URL}}"
  service_id     = railway_service.n8n[0].id
  environment_id = railway_environment.main.id
}

# Webhook handler service — receives forwarded webhooks from Cloudflare Worker.
resource "railway_service" "webhook_handler" {
  count      = var.enable_webhooks ? 1 : 0
  name       = "webhook-handler"
  project_id = var.railway_project_id

  source_image = "python:3.12-slim"
}

resource "railway_variable" "webhook_secret" {
  count          = var.enable_webhooks ? 1 : 0
  name           = "GITHUB_WEBHOOK_SECRET"
  value          = random_password.webhook_secret.result
  service_id     = railway_service.webhook_handler[0].id
  environment_id = railway_environment.main.id
}

# Store webhook secret in GCP SM for reference by Cloudflare Worker.
resource "google_secret_manager_secret" "webhook_secret" {
  count     = var.enable_webhooks ? 1 : 0
  project   = var.gcp_project_id
  secret_id = "github-webhook-secret"
  replication { auto {} }
}

resource "google_secret_manager_secret_version" "webhook_secret" {
  count       = var.enable_webhooks ? 1 : 0
  secret      = google_secret_manager_secret.webhook_secret[0].id
  secret_data = random_password.webhook_secret.result
}

output "n8n_service_id" {
  value = var.enable_n8n ? railway_service.n8n[0].id : ""
}

output "environment_id" {
  value = railway_environment.main.id
}

output "webhook_handler_url" {
  value = var.enable_webhooks ? railway_service.webhook_handler[0].url : ""
}

output "webhook_secret" {
  value     = random_password.webhook_secret.result
  sensitive = true
}
