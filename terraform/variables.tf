variable "gcp_project_id" {
  type = string
  description = "The ID of the Google Cloud project where resources will be deployed."
}

variable "gcp_region" {
  type        = string
  description = "Default GCP region for the provider and regional resources."
}

variable "raw_bucket_name" {
  type        = string
  description = "The name of the GCS bucket for storing raw ingested space launch data."

}
