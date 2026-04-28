variable "gcp_project_id" {
  description = "GCP project ID for infrastructure provisioning"
  type        = string
}

variable "github_org" {
  description = "GitHub organization or user that owns the repository"
  type        = string
}

variable "repo_name" {
  description = "Target repository name (without org prefix)"
  type        = string
  default     = ""
}

variable "github_app_id" {
  description = "GitHub App ID (created manually in GitHub Developer Settings)"
  type        = string
}

variable "enable_railway" {
  description = "Deploy Railway services (N8N, Postgres, webhook handler)"
  type        = bool
  default     = false
}

variable "enable_cloudflare" {
  description = "Deploy Cloudflare Workers webhook gateway"
  type        = bool
  default     = false
}

variable "enable_n8n" {
  description = "Deploy N8N workflow engine on Railway"
  type        = bool
  default     = false
}

variable "railway_workspace_id" {
  description = "Railway workspace ID (required if enable_railway = true)"
  type        = string
  default     = ""
}

variable "cloudflare_account_id" {
  description = "Cloudflare account ID (required if enable_cloudflare = true)"
  type        = string
  default     = ""
}

variable "cloudflare_zone_id" {
  description = "Cloudflare zone ID for routing (required if enable_cloudflare = true)"
  type        = string
  default     = ""
}

variable "cloudflare_domain" {
  description = "Domain managed by Cloudflare (required if enable_cloudflare = true)"
  type        = string
  default     = ""
}
