# Retail Omnichannel - BigQuery Datasets e Infraestrutura
# Supabase project: emqwecqytddkpwcjybfl

variable "retail_project_id" {
  description = "GCP Project ID para os dados de varejo"
  type        = string
}

variable "retail_region" {
  description = "Região BigQuery"
  type        = string
  default     = "us-east1"
}

# ============================================================
# DATASETS - Arquitetura Medallion (Bronze / Silver / Gold)
# ============================================================

resource "google_bigquery_dataset" "retail_bronze" {
  project       = var.retail_project_id
  dataset_id    = "retail_bronze"
  friendly_name = "Retail Bronze - Staging (replicação Supabase bruta)"
  location      = var.retail_region
  description   = "Camada de landing idêntica à origem Supabase. Sem transformações."

  labels = {
    env   = "production"
    layer = "bronze"
    source = "supabase-cdc"
  }
}

resource "google_bigquery_dataset" "retail_silver" {
  project       = var.retail_project_id
  dataset_id    = "retail_silver"
  friendly_name = "Retail Silver - Star Schema modelado"
  location      = var.retail_region
  description   = "Star Schema com deduplicação, tipagem e chaves. Fonte de verdade para BI e IA."

  labels = {
    env   = "production"
    layer = "silver"
  }
}

resource "google_bigquery_dataset" "retail_gold" {
  project       = var.retail_project_id
  dataset_id    = "retail_gold"
  friendly_name = "Retail Gold - OBT e Métricas (Gemini-ready)"
  location      = var.retail_region
  description   = "Views flat (One Big Table) para Gemini Studio, LTV/CAC/ROAS e dashboards."

  labels = {
    env   = "production"
    layer = "gold"
  }
}

resource "google_bigquery_dataset" "retail_ml" {
  project       = var.retail_project_id
  dataset_id    = "retail_ml"
  friendly_name = "Retail ML - Modelos BQML e Embeddings"
  location      = var.retail_region
  description   = "Modelos ARIMA_PLUS, embeddings de produto e outputs de previsão de demanda."

  labels = {
    env   = "production"
    layer = "ml"
  }
}

# ============================================================
# IAM - Service Account para Datastream -> BigQuery
# ============================================================

resource "google_service_account" "datastream_sa" {
  project      = var.retail_project_id
  account_id   = "retail-datastream-sa"
  display_name = "Datastream CDC - Supabase para BigQuery"
}

resource "google_bigquery_dataset_iam_member" "datastream_bronze_editor" {
  project    = var.retail_project_id
  dataset_id = google_bigquery_dataset.retail_bronze.dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:${google_service_account.datastream_sa.email}"
}

resource "google_project_iam_member" "datastream_job_user" {
  project = var.retail_project_id
  role    = "roles/bigquery.jobUser"
  member  = "serviceAccount:${google_service_account.datastream_sa.email}"
}

# ============================================================
# APIs necessárias
# ============================================================

resource "google_project_service" "retail_apis" {
  for_each = toset([
    "bigquery.googleapis.com",
    "datastream.googleapis.com",
    "dataplex.googleapis.com",
    "bigquerymigration.googleapis.com",
  ])
  project            = var.retail_project_id
  service            = each.value
  disable_on_destroy = false
}
