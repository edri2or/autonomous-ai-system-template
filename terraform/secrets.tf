# GCP Secret Manager resources
#
# IMPORTANT: The github-app-private-key secret MUST be pre-populated before
# running Terraform. Bootstrap script handles this via verify-gate-001.sh.
# See docs/gates/manual-gates.md — GATE-001.

resource "google_secret_manager_secret" "github_app_private_key" {
  project   = var.gcp_project_id
  secret_id = "github-app-private-key"

  replication {
    auto {}
  }

  labels = {
    purpose = "github-app-auth"
    managed = "terraform"
  }
}

resource "google_secret_manager_secret_iam_member" "github_app_key_access" {
  secret_id = google_secret_manager_secret.github_app_private_key.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.terraform.email}"
}

resource "google_secret_manager_secret" "github_app_id" {
  project   = var.gcp_project_id
  secret_id = "github-app-id"

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "github_app_id" {
  secret      = google_secret_manager_secret.github_app_id.id
  secret_data = var.github_app_id
}

resource "google_secret_manager_secret_iam_member" "github_app_id_access" {
  secret_id = google_secret_manager_secret.github_app_id.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.terraform.email}"
}
