# Workload Identity Federation — ADR-0103 (branch-scoped)

resource "google_iam_workload_identity_pool" "github" {
  project = var.gcp_project_id

  workload_identity_pool_id = "github-pool"
  location                  = "global"
  display_name              = "GitHub Actions"
  description               = "WIF pool for GitHub Actions OIDC tokens"
}

resource "google_iam_workload_identity_pool_provider" "github" {
  project = var.gcp_project_id

  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-provider"
  location                           = "global"
  display_name                       = "GitHub Provider"

  attribute_mapping = {
    "google.subject"             = "assertion.sub"
    "assertion.aud"              = "assertion.aud"
    "assertion.repository"       = "assertion.repository"
    "assertion.repository_owner" = "assertion.repository_owner"
    "assertion.ref"              = "assertion.ref"
  }

  # ADR-0103: Scope to specific repo + main branch only
  attribute_condition = "assertion.repository == '${var.github_org}/${local.repo_name}' && assertion.ref == 'refs/heads/main'"

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

resource "google_service_account" "terraform" {
  project      = var.gcp_project_id
  account_id   = "terraform-bootstrap"
  display_name = "Terraform Bootstrap SA"
  description  = "Service account used by GitHub Actions via WIF"
}

resource "google_service_account_iam_binding" "wif_binding" {
  service_account_id = google_service_account.terraform.name
  role               = "roles/iam.workloadIdentityUser"

  members = [
    "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.github_org}/${local.repo_name}",
  ]
}

resource "google_project_iam_member" "secret_manager_accessor" {
  project = var.gcp_project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.terraform.email}"
}

output "wif_provider_resource_name" {
  value       = "projects/${data.google_client_config.current.project}/locations/global/workloadIdentityPools/${google_iam_workload_identity_pool.github.workload_identity_pool_id}/providers/${google_iam_workload_identity_pool_provider.github.workload_identity_pool_provider_id}"
  description = "WIF provider resource name — store as GCP_WORKLOAD_IDENTITY_PROVIDER GitHub Secret"
}

output "service_account_email" {
  value       = google_service_account.terraform.email
  description = "Terraform SA email — store as GCP_SERVICE_ACCOUNT_EMAIL GitHub Secret"
}
