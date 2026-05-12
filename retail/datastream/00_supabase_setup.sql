-- =============================================================
-- EXECUTAR NO SUPABASE SQL EDITOR:
-- https://supabase.com/dashboard/project/emqwecqytddkpwcjybfl/sql
--
-- PRÉ-REQUISITO para ativar Google Cloud Datastream CDC
-- Executar os blocos na ordem (1 → 2 → 3 → 4)
-- =============================================================

-- =============================================================
-- BLOCO 1: Criar usuário de replicação para Datastream
-- =============================================================
CREATE ROLE datastream_user WITH REPLICATION LOGIN PASSWORD 'TROCAR_POR_SENHA_SEGURA';

GRANT USAGE ON SCHEMA public TO datastream_user;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO datastream_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO datastream_user;

-- =============================================================
-- BLOCO 2: Criar Publication com TODAS as tabelas retail
-- O Datastream escuta esta publication para capturar mudanças
-- =============================================================
CREATE PUBLICATION datastream_retail_pub
FOR TABLE
  public."Vendas_Header",
  public.vendas_itens,
  public.clientes,
  public.produtos,
  public.marcas,
  public."Lojas",
  public.fornecedores,
  public.funcionarios,
  public.meios_pagamento,
  public.financeiro;

-- =============================================================
-- BLOCO 3: Criar Replication Slot lógico
-- ATENÇÃO: O Supabase já tem wal_level=logical por padrão
-- =============================================================
SELECT pg_create_logical_replication_slot('datastream_retail_slot', 'pgoutput');

-- =============================================================
-- BLOCO 4: Verificar que tudo foi criado corretamente
-- Esperar resultado com 1 linha para o slot
-- =============================================================

-- 4a. Verificar replication slot
SELECT slot_name, plugin, slot_type, active
FROM pg_replication_slots
WHERE slot_name = 'datastream_retail_slot';
-- ESPERADO: datastream_retail_slot | pgoutput | logical | f

-- 4b. Verificar publication e tabelas vinculadas
SELECT * FROM pg_publication WHERE pubname = 'datastream_retail_pub';

SELECT schemaname, tablename
FROM pg_publication_tables
WHERE pubname = 'datastream_retail_pub'
ORDER BY tablename;
-- ESPERADO: 10 tabelas listadas

-- 4c. Verificar permissões do usuário
SELECT rolname, rolreplication, rolcanlogin
FROM pg_roles
WHERE rolname = 'datastream_user';
-- ESPERADO: datastream_user | t | t

-- =============================================================
-- APÓS EXECUTAR:
-- 1. Copiar a senha usada no BLOCO 1
-- 2. Salvar no Google Cloud Secret Manager:
--    gcloud secrets create supabase-datastream-pwd \
--      --data-file=- <<< "TROCAR_POR_SENHA_SEGURA" \
--      --project=SEU_PROJECT_ID
-- 3. Liberar IP do Datastream no Supabase:
--    Dashboard > Settings > Database > Network
--    Adicionar IP range do Datastream (ver documentação GCP)
-- 4. Rodar: terraform apply nos módulos retail/
-- =============================================================
