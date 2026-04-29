# Cross-project IAM bindings for accessing centralized secrets hub
#
# The Terraform SA in this project needs read access to secrets stored in the
# centralized secrets hub project (or-infra-admin-hub). This binding grants
# secretAccessor role on specific secrets.
#
# Secrets accessed from hub:
# - github-app-private-key (GitHub App authentication)
# - github-app-id (GitHub App ID)
# - railway-api-token (if enable_railway = true)
# - cloudflare-api-token (if enable_cloudflare = true)
# - cloudflare-zone-id (if enable_cloudflare = true)

# ── GitHub App credentials (always required) ──────────────────────────────────

resource "google_secret_manager_secret_iam_member" "github_app_private_key_from_hub" {
  secret_id = "projects/${var.secrets_hub_project_id}/secrets/github-app-private-key"
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.terraform.email}"
}

resource "google_secret_manager_secret_iam_member" "github_app_id_from_hub" {
  secret_id = "projects/${var.secrets_hub_project_id}/secrets/github-app-id"
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.terraform.email}"
}

# ── Railway credentials (conditional) ─────────────────────────────────────────

resource "google_secret_manager_secret_iam_member" "railway_api_token_from_hub" {
  count     = var.enable_railway ? 1 : 0
  secret_id = "projects/${var.secrets_hub_project_id}/secrets/railway-api-token"
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.terraform.email}"
}

# ── Cloudflare credentials (conditional) ──────────────────────────────────────

resource "google_secret_manager_secret_iam_member" "cloudflare_api_token_from_hub" {
  count     = var.enable_cloudflare ? 1 : 0
  secret_id = "projects/${var.secrets_hub_project_id}/secrets/cloudflare-api-token"
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.terraform.email}"
}

resource "google_secret_manager_secret_iam_member" "cloudflare_zone_id_from_hub" {
  count     = var.enable_cloudflare ? 1 : 0
  secret_id = "projects/${var.secrets_hub_project_id}/secrets/cloudflare-zone-id"
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.terraform.email}"
}
