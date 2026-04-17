# =============================================================
# Google Cloud Datastream - CDC Supabase -> BigQuery
# Fonte: Supabase PostgreSQL (projeto: emqwecqytddkpwcjybfl)
# Destino: BigQuery retail_bronze
# Estratégia: CDC via replication slot PostgreSQL (wal_level=logical)
#
# PRÉ-REQUISITO no Supabase:
#   1. Habilitar replication slot: wal_level = logical (padrão no Supabase)
#   2. Criar usuário de replicação com permissões SELECT + REPLICATION
#   3. Liberar IP do Datastream no Supabase Network > Connection Pooling
#
# Senha do usuário: armazenar no Secret Manager, NÃO em variável plaintext
# =============================================================

variable "datastream_supabase_password_secret" {
  description = "ID do secret no Secret Manager com a senha do usuário de replicação"
  type        = string
  sensitive   = true
}

variable "datastream_supabase_host" {
  description = "Host PostgreSQL do Supabase (ex: db.emqwecqytddkpwcjybfl.supabase.co)"
  type        = string
  default     = "db.emqwecqytddkpwcjybfl.supabase.co"
}

data "google_secret_manager_secret_version" "supabase_pwd" {
  project = var.retail_project_id
  secret  = var.datastream_supabase_password_secret
}

# -----------------------------------------------------------
# Connection Profile - Origem: Supabase PostgreSQL
# -----------------------------------------------------------
resource "google_datastream_connection_profile" "supabase_source" {
  project               = var.retail_project_id
  location              = var.retail_region
  display_name          = "Supabase Retail - PostgreSQL CDC"
  connection_profile_id = "supabase-retail-source"

  postgresql_profile {
    hostname = var.datastream_supabase_host
    port     = 5432
    username = "postgres"
    password = data.google_secret_manager_secret_version.supabase_pwd.secret_data
    database = "postgres"
  }

  labels = {
    source  = "supabase"
    project = "emqwecqytddkpwcjybfl"
    env     = "production"
  }
}

# -----------------------------------------------------------
# Connection Profile - Destino: BigQuery
# -----------------------------------------------------------
resource "google_datastream_connection_profile" "bigquery_destination" {
  project               = var.retail_project_id
  location              = var.retail_region
  display_name          = "BigQuery Retail Bronze"
  connection_profile_id = "bigquery-retail-destination"

  bigquery_profile {}
}

# -----------------------------------------------------------
# Stream de CDC - Tabelas de Alta Frequência
# Prioridade 1: Vendas (> 50k linhas, atualização contínua)
# -----------------------------------------------------------
resource "google_datastream_stream" "retail_vendas_stream" {
  project       = var.retail_project_id
  location      = var.retail_region
  stream_id     = "retail-vendas-cdc"
  display_name  = "CDC Retail - Vendas e Clientes (Alta Frequência)"
  desired_state = "RUNNING"

  source_config {
    source_connection_profile = google_datastream_connection_profile.supabase_source.id

    postgresql_source_config {
      max_concurrent_backfill_tasks = 12
      replication_slot              = "datastream_retail_slot"
      publication                   = "datastream_retail_pub"

      include_objects {
        postgresql_schemas {
          schema = "public"

          # Vendas_Header: 54.601 linhas, 252 colunas, updated_at disponível
          postgresql_tables {
            table = "Vendas_Header"
          }

          # vendas_itens: 43.936 linhas, 199 colunas, data_at como timestamp
          # ATENÇÃO: sem PK explícita - Datastream usará rowid/ctid
          postgresql_tables {
            table = "vendas_itens"
          }

          # clientes: 69.566 linhas, updated_at disponível
          postgresql_tables {
            table = "clientes"
          }
        }
      }
    }
  }

  destination_config {
    destination_connection_profile = google_datastream_connection_profile.bigquery_destination.id

    bigquery_destination_config {
      single_target_dataset {
        dataset_id = "${var.retail_project_id}:${google_bigquery_dataset.retail_bronze.dataset_id}"
      }

      data_freshness = "300s"
    }
  }

  backfill_all {}

  labels = {
    priority  = "high"
    tables    = "vendas-clientes"
  }
}

# -----------------------------------------------------------
# Stream de CDC - Dimensões (Baixa Frequência)
# produtos, marcas, lojas, fornecedores, funcionarios, meios_pagamento
# -----------------------------------------------------------
resource "google_datastream_stream" "retail_dims_stream" {
  project       = var.retail_project_id
  location      = var.retail_region
  stream_id     = "retail-dims-cdc"
  display_name  = "CDC Retail - Dimensões (Baixa Frequência)"
  desired_state = "RUNNING"

  source_config {
    source_connection_profile = google_datastream_connection_profile.supabase_source.id

    postgresql_source_config {
      max_concurrent_backfill_tasks = 4
      replication_slot              = "datastream_retail_slot"
      publication                   = "datastream_retail_pub"

      include_objects {
        postgresql_schemas {
          schema = "public"

          postgresql_tables { table = "produtos" }         # 8.415 linhas, updated_at
          postgresql_tables { table = "marcas" }           # 354 linhas, data_atualizacao
          postgresql_tables { table = "Lojas" }            # 12 linhas, PK: codigo_loja
          postgresql_tables { table = "fornecedores" }     # 48 linhas, created_at
          postgresql_tables { table = "funcionarios" }     # 119 linhas, PK composta
          postgresql_tables { table = "meios_pagamento" }  # 22 linhas
          postgresql_tables { table = "financeiro" }       # 0 linhas (preparado)
        }
      }
    }
  }

  destination_config {
    destination_connection_profile = google_datastream_connection_profile.bigquery_destination.id

    bigquery_destination_config {
      single_target_dataset {
        dataset_id = "${var.retail_project_id}:${google_bigquery_dataset.retail_bronze.dataset_id}"
      }

      data_freshness = "900s"
    }
  }

  backfill_all {}

  labels = {
    priority = "low"
    tables   = "dimensoes"
  }
}

# -----------------------------------------------------------
# COMANDOS SQL para executar no Supabase antes do Datastream
# Executar via Supabase SQL Editor:
# https://supabase.com/dashboard/project/emqwecqytddkpwcjybfl/sql
# -----------------------------------------------------------
# -- 1. Criar usuário de replicação
# CREATE ROLE datastream_user REPLICATION LOGIN PASSWORD 'SENHA_SEGURA';
# GRANT SELECT ON ALL TABLES IN SCHEMA public TO datastream_user;
# ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO datastream_user;
#
# -- 2. Criar publication para as tabelas de vendas
# CREATE PUBLICATION datastream_retail_pub
#   FOR TABLE public."Vendas_Header", public.vendas_itens, public.clientes,
#              public.produtos, public.marcas, public."Lojas",
#              public.fornecedores, public.funcionarios,
#              public.meios_pagamento, public.financeiro;
#
# -- 3. Criar replication slot
# SELECT pg_create_logical_replication_slot('datastream_retail_slot', 'pgoutput');
#
# -- 4. Verificar slot criado
# SELECT * FROM pg_replication_slots WHERE slot_name = 'datastream_retail_slot';
