terraform {
  backend "gcs" {
    bucket = "space-analytics-tfstate"
  }
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "8.8.1"
    }
  }
}

provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region
}
