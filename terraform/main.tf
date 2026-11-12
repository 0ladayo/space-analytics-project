locals {
  gcp_services = toset([
    "storage.googleapis.com",
    "cloudbuild.googleapis.com",
    "run.googleapis.com",
    "artifactregistry.googleapis.com",
    "iam.googleapis.com",
    "secretmanager.googleapis.com",
    "cloudscheduler.googleapis.com",
    "bigquery.googleapis.com",
    "eventarc.googleapis.com",
    "pubsub.googleapis.com",
  ])

  service_account_roles = toset([
    "roles/run.admin",
    "roles/run.builder",
    "roles/run.sourceDeveloper",
    "roles/iam.serviceAccountUser",
    "roles/cloudbuild.connectionViewer",
    "roles/bigquery.jobUser",
    "roles/eventarc.eventReceiver",
  ])

  github_repository = "projects/${var.gcp_project_id}/locations/${var.gcp_region}/connections/github-connection/repositories/0ladayo-space-analytics-project"
}

resource "google_project_service" "gcp_services" {
  for_each = local.gcp_services

  project            = var.gcp_project_id
  service            = each.value
  disable_on_destroy = false
}

resource "google_service_account" "service_account" {
  account_id   = "space-analytics-sa"
  display_name = "Space Analytics Pipeline Service Account"

  depends_on = [
    google_project_service.gcp_services,
  ]
}

resource "google_project_iam_member" "service_account_roles" {
  for_each = local.service_account_roles

  project = var.gcp_project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.service_account.email}"
}

data "google_storage_project_service_account" "gcs_account" {
  depends_on = [
    google_project_service.gcp_services,
  ]
}

resource "google_project_iam_member" "gcs_pubsub_publisher" {
  project = var.gcp_project_id
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${data.google_storage_project_service_account.gcs_account.email_address}"
}

resource "google_storage_bucket" "raw_bucket" {
  name          = var.raw_bucket_name
  location      = var.gcp_region
  force_destroy = true

  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  depends_on = [
    google_project_service.gcp_services,
  ]
}

resource "google_storage_bucket_iam_member" "raw_bucket_object_user" {
  bucket = google_storage_bucket.raw_bucket.name
  role   = "roles/storage.admin"
  member = "serviceAccount:${google_service_account.service_account.email}"
}

resource "google_bigquery_dataset" "raw_dataset" {
  dataset_id = var.bigquery_dataset_id
  location   = var.gcp_region

  depends_on = [
    google_project_service.gcp_services,
  ]
}

resource "google_bigquery_dataset_iam_member" "raw_dataset_data_editor" {
  dataset_id = google_bigquery_dataset.raw_dataset.dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:${google_service_account.service_account.email}"
}

resource "google_bigquery_table" "launches_table" {
  dataset_id          = google_bigquery_dataset.raw_dataset.dataset_id
  table_id            = var.bigquery_table_id
  deletion_protection = false

  time_partitioning {
    type  = "YEAR"
    field = "net"
  }

  clustering = ["agency_name", "status_abbrev"]

  schema = jsonencode([
    { name = "launch_id", type = "STRING", mode = "REQUIRED" },
    { name = "launch_name", type = "STRING", mode = "NULLABLE" },
    { name = "last_updated", type = "TIMESTAMP", mode = "NULLABLE" },
    { name = "net", type = "TIMESTAMP", mode = "NULLABLE" },
    { name = "window_start", type = "TIMESTAMP", mode = "NULLABLE" },
    { name = "window_end", type = "TIMESTAMP", mode = "NULLABLE" },
    { name = "status_name", type = "STRING", mode = "NULLABLE" },
    { name = "status_abbrev", type = "STRING", mode = "NULLABLE" },
    { name = "fail_reason", type = "STRING", mode = "NULLABLE" },
    { name = "agency_id", type = "INT64", mode = "NULLABLE" },
    { name = "agency_name", type = "STRING", mode = "NULLABLE" },
    { name = "agency_type", type = "STRING", mode = "NULLABLE" },
    { name = "agency_country", type = "STRING", mode = "NULLABLE" },
    { name = "rocket_id", type = "INT64", mode = "NULLABLE" },
    { name = "rocket_name", type = "STRING", mode = "NULLABLE" },
    { name = "mission_name", type = "STRING", mode = "NULLABLE" },
    { name = "mission_type", type = "STRING", mode = "NULLABLE" },
    { name = "orbit_name", type = "STRING", mode = "NULLABLE" },
    { name = "orbit_abbrev", type = "STRING", mode = "NULLABLE" },
    { name = "pad_id", type = "INT64", mode = "NULLABLE" },
    { name = "pad_name", type = "STRING", mode = "NULLABLE" },
    { name = "location_name", type = "STRING", mode = "NULLABLE" },
    { name = "latitude", type = "FLOAT64", mode = "NULLABLE" },
    { name = "longitude", type = "FLOAT64", mode = "NULLABLE" },
    { name = "pad_total_launches", type = "INT64", mode = "NULLABLE" },
  ])
}

resource "google_cloudbuild_trigger" "ingestion_build_trigger" {
  location        = var.gcp_region
  name            = "ingestion-build-trigger"
  filename        = "ingestion/ingestion.cloudbuild.yaml"
  service_account = google_service_account.service_account.id

  included_files = [
    "ingestion/**",
  ]

  repository_event_config {
    repository = local.github_repository
    push {
      branch = "^main$"
    }
  }

  substitutions = {
    _LOCATION              = var.gcp_region
    _RAW_BUCKET_NAME       = var.raw_bucket_name
    _SERVICE_ACCOUNT_EMAIL = google_service_account.service_account.email
  }

  depends_on = [
    google_project_iam_member.service_account_roles,
  ]
}

resource "google_cloudbuild_trigger" "loading_build_trigger" {
  location        = var.gcp_region
  name            = "loading-build-trigger"
  filename        = "loading/loading.cloudbuild.yaml"
  service_account = google_service_account.service_account.id

  included_files = [
    "loading/**",
  ]

  repository_event_config {
    repository = local.github_repository
    push {
      branch = "^main$"
    }
  }

  substitutions = {
    _LOCATION              = var.gcp_region
    _SERVICE_ACCOUNT_EMAIL = google_service_account.service_account.email
    _BIGQUERY_TABLE_ID     = "${var.gcp_project_id}.${google_bigquery_dataset.raw_dataset.dataset_id}.${google_bigquery_table.launches_table.table_id}"
  }

  depends_on = [
    google_project_iam_member.service_account_roles,
  ]
}

resource "google_eventarc_trigger" "loading_gcs_trigger" {
  name            = "loading-gcs-trigger"
  location        = var.gcp_region
  service_account = google_service_account.service_account.email

  matching_criteria {
    attribute = "type"
    value     = "google.cloud.storage.object.v1.finalized"
  }

  matching_criteria {
    attribute = "bucket"
    value     = google_storage_bucket.raw_bucket.name
  }

  destination {
    cloud_run_service {
      service = "loading-service"
      region  = var.gcp_region
    }
  }

  depends_on = [
    google_project_iam_member.service_account_roles,
    google_project_iam_member.gcs_pubsub_publisher,
  ]
}

resource "google_cloud_scheduler_job" "ingestion_cron_job" {
  name             = "ingestion-cron-job"
  region           = var.gcp_region
  schedule         = "0 */12 * * *"
  time_zone        = "Europe/London"
  attempt_deadline = "320s"

  retry_config {
    retry_count = 1
  }

  http_target {
    http_method = "POST"
    uri         = "https://${var.gcp_region}-run.googleapis.com/apis/run.googleapis.com/v1/namespaces/${var.gcp_project_id}/jobs/ingestion-job:run"

    oauth_token {
      service_account_email = google_service_account.service_account.email
    }
  }

  depends_on = [
    google_project_iam_member.service_account_roles,
  ]
}
