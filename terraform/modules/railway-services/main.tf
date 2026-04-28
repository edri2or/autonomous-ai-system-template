terraform {
  required_providers {
    railway = {
      source  = "brainly/railway"
      version = "~> 0.2"
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

variable "environment_name" { type = string }
variable "enable_postgresql" { type = bool; default = true }
variable "enable_n8n"        { type = bool; default = false }
variable "enable_webhooks"   { type = bool; default = true }
variable "gcp_project_id"   { type = string }
variable "railway_project_id" {
  type    = string
  default = ""
}
variable "railway_domain" {
  type    = string
  default = ""
}

resource "random_password" "postgres" {
  length  = 24
  special = false
}

resource "random_password" "webhook_secret" {
  length  = 32
  special = false
}

resource "railway_environment" "main" {
  name       = var.environment_name
  project_id = var.railway_project_id
}

resource "railway_service" "postgres" {
  count = var.enable_postgresql ? 1 : 0

  name     = "postgres"
  owner_id = railway_environment.main.id

  source {
    image = "postgres:15"
  }

  config = {
    PORT              = "5432"
    POSTGRES_PASSWORD = random_password.postgres.result
  }
}

resource "railway_service" "n8n" {
  count = var.enable_n8n ? 1 : 0

  name     = "n8n"
  owner_id = railway_environment.main.id

  source {
    image = "n8nio/n8n:latest"
  }

  config = {
    N8N_HOST = var.railway_domain
    N8N_PORT = "5678"
    DB_TYPE  = "postgresdb"
  }

  depends_on = [railway_service.postgres]
}

resource "railway_service" "webhook_handler" {
  count = var.enable_webhooks ? 1 : 0

  name     = "webhook-handler"
  owner_id = railway_environment.main.id

  source {
    path = "webhook-handler/"
  }

  config = {
    PORT                   = "8000"
    GITHUB_WEBHOOK_SECRET  = random_password.webhook_secret.result
  }
}

resource "google_secret_manager_secret" "postgres_password" {
  project   = var.gcp_project_id
  secret_id = "railway-postgres-password"

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "postgres_password" {
  secret      = google_secret_manager_secret.postgres_password.id
  secret_data = random_password.postgres.result
}

output "postgres_connection_string" {
  value     = var.enable_postgresql ? railway_service.postgres[0].connection_string : ""
  sensitive = true
}

output "n8n_url" {
  value = var.enable_n8n ? railway_service.n8n[0].public_url : ""
}

output "webhook_handler_url" {
  value = var.enable_webhooks ? railway_service.webhook_handler[0].public_url : ""
}

output "webhook_secret" {
  value     = random_password.webhook_secret.result
  sensitive = true
}
