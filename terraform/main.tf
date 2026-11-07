resource "google_service_account" "service_account" {
  account_id   = "space-analytics-sa"
  display_name = "Space Analytics Pipeline Service Account"
}

locals {
  service_account_roles = toset([
    "roles/run.admin",
    "roles/run.sourceDeveloper",
    "roles/run.builder",
    "roles/iam.serviceAccountUser",
  ])
}

resource "google_project_iam_member" "service_account_roles" {
  for_each = local.service_account_roles

  project = var.gcp_project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.service_account.email}"
}

resource "google_storage_bucket" "raw_bucket" {
  name          = var.raw_bucket_name
  location      = var.gcp_region
  force_destroy = true

  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
}

resource "google_storage_bucket_iam_member" "raw_bucket_object_user" {
  bucket = google_storage_bucket.raw_bucket.name
  role   = "roles/storage.objectUser"
  member = "serviceAccount:${google_service_account.service_account.email}"
}

resource "google_cloudbuild_trigger" "ingestion_build_trigger" {
  location        = var.gcp_region
  name            = "ingestion-build-trigger"
  filename        = "ingestion/ingestion.cloudbuild.yaml"
  service_account = google_service_account.service_account.id

  included_files = [
    "ingestion/**",
    "pyproject.toml",
    "uv.lock",
  ]

  repository_event_config {
    repository = "projects/${var.gcp_project_id}/locations/${var.gcp_region}/connections/github-connection/repositories/0ladayo-space-analytics-project"
    push {
      branch = "^main$"
    }
  }

  substitutions = {
    _LOCATION              = var.gcp_region
    _PROJECT_ID            = var.gcp_project_id
    _RAW_BUCKET_NAME       = var.raw_bucket_name
    _SERVICE_ACCOUNT_EMAIL = google_service_account.service_account.email
  }

  depends_on = [
    google_project_iam_member.service_account_roles,
  ]
}
