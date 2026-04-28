# GCP Secret Manager resources
#
# GATE-001 requires github-app-private-key to be pre-created in GCP SM before
# running Terraform. We reference it as a data source to avoid a conflict on
# apply (creating a resource that already exists returns HTTP 409).
#
# github-app-id is fully managed by Terraform (created + versioned here).

data "google_secret_manager_secret" "github_app_private_key" {
  project   = var.gcp_project_id
  secret_id = "github-app-private-key"
}

resource "google_secret_manager_secret_iam_member" "github_app_key_access" {
  secret_id = data.google_secret_manager_secret.github_app_private_key.id
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
