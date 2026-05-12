# Deploy - Retail Omnichannel (Supabase + BigQuery)

## Sequência de execução

### Passo 1 — Supabase (10 min)

1. Abra: https://supabase.com/dashboard/project/emqwecqytddkpwcjybfl/sql
2. Cole e execute `retail/datastream/00_supabase_setup.sql` (blocos 1→4)
3. **TROQUE** a senha `TROCAR_POR_SENHA_SEGURA` por uma senha forte
4. Valide que o BLOCO 4 retorna os resultados esperados

### Passo 2 — Secret Manager (5 min)

```bash
gcloud secrets create supabase-datastream-pwd \
  --data-file=- <<< "SUA_SENHA_AQUI" \
  --project=SEU_PROJECT_ID
```

### Passo 3 — Liberar IP do Datastream no Supabase (5 min)

1. Dashboard Supabase → Settings → Database → Network
2. Adicionar IP range do Google Cloud Datastream da sua região

### Passo 4 — Terraform Apply (30 min)

```bash
cd retail/terraform
terraform init
terraform apply \
  -var="retail_project_id=SEU_PROJECT_ID" \
  -var="retail_region=us-east1"

cd ../datastream
terraform init
terraform apply \
  -var="retail_project_id=SEU_PROJECT_ID" \
  -var="retail_region=us-east1" \
  -var="datastream_supabase_password_secret=supabase-datastream-pwd"
```

### Passo 5 — Executar SQLs no BigQuery Console (15 min)

Rodar na ordem:
1. `retail/sql/bronze/01_staging_tables.sql`
2. `retail/sql/silver/02_star_schema.sql`
3. `retail/sql/gold/03_view_vendas_360.sql`
4. `retail/sql/gold/04_metricas_ltv_cac_roas.sql`
5. `retail/sql/bqml/05_modelo_demanda_arima.sql`

### Passo 6 — Validar dados (10 min)

```sql
-- Verificar se Datastream está replicando
SELECT COUNT(*) FROM `retail_bronze.vendas_header`;
-- Esperado: ~54.601

-- Verificar Star Schema
SELECT COUNT(*) FROM `retail_silver.fact_vendas`;

-- Verificar OBT
SELECT * FROM `retail_gold.view_vendas_360` LIMIT 10;
```

## Itens pendentes pós-deploy

| Item | Depende de | Estimativa |
|------|-----------|------------|
| Google Ads Data Transfer | Console GCP > BigQuery > Transfers | 20 min |
| Meta Ads Connector | Fivetran/Airbyte ou API custom | 1-2h |
| Server-Side Tagging | Google Tag Manager Server Container | 2-4h |
| Atualizar placeholders CAC/ROAS | Itens acima prontos | 30 min |
| Dashboard Looker/Data Studio | Dados fluindo | 2-4h |
