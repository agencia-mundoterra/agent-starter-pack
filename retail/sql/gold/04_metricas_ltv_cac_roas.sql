-- =============================================================
-- GOLD LAYER - Métricas de ROI Omnichannel
-- LTV / CAC / ROAS
-- Dataset: retail_gold
-- =============================================================

-- -----------------------------------------------------------
-- VIEW: ltv_clientes
-- LTV = Ticket Médio x Frequência de Compra x Tempo de Vida (meses)
-- -----------------------------------------------------------
CREATE OR REPLACE VIEW `retail_gold.view_ltv_clientes`
OPTIONS(description="Life Time Value por cliente. LTV = ticket_medio * freq_mensal * meses_ativo. Usar para segmentação e corte de CAC.")
AS
WITH compras_por_cliente AS (
  SELECT
    cliente_sk,
    cpf_cnpj_hash,
    cliente_nome,
    cliente_email,
    cliente_uf,
    tipo_cliente,
    MIN(data_venda)     AS primeira_compra,
    MAX(data_venda)     AS ultima_compra,
    COUNT(DISTINCT venda_sk)        AS total_pedidos,
    COUNT(DISTINCT controle_itens)  AS total_itens,
    SUM(valor_liquido_item_r$)      AS receita_total,
    SUM(lucro_item_r$)              AS lucro_total,
    COUNT(DISTINCT canal_venda)     AS canais_utilizados,
    STRING_AGG(DISTINCT canal_venda ORDER BY canal_venda) AS canais
  FROM `retail_gold.view_vendas_360`
  WHERE status_venda NOT IN ('CANCELADO', 'CANCELADA')
  GROUP BY 1, 2, 3, 4, 5, 6
)
SELECT
  *,
  ROUND(receita_total / NULLIF(total_pedidos, 0), 2)          AS ticket_medio,
  DATE_DIFF(ultima_compra, primeira_compra, MONTH) + 1        AS meses_ativo,
  ROUND(total_pedidos / NULLIF(
    DATE_DIFF(ultima_compra, primeira_compra, MONTH) + 1, 0
  ), 2)                                                        AS freq_compras_por_mes,
  -- LTV projetado (fórmula clássica)
  ROUND(
    (receita_total / NULLIF(total_pedidos, 0)) *
    (total_pedidos / NULLIF(DATE_DIFF(ultima_compra, primeira_compra, MONTH) + 1, 0)) *
    (DATE_DIFF(ultima_compra, primeira_compra, MONTH) + 1),
  2)                                                           AS ltv_r$,
  -- Segmentação RFM simplificada
  CASE
    WHEN DATE_DIFF(CURRENT_DATE(), ultima_compra, DAY) <= 30  THEN 'ATIVO_RECENTE'
    WHEN DATE_DIFF(CURRENT_DATE(), ultima_compra, DAY) <= 90  THEN 'ATIVO'
    WHEN DATE_DIFF(CURRENT_DATE(), ultima_compra, DAY) <= 180 THEN 'EM_RISCO'
    ELSE 'INATIVO'
  END                                                          AS segmento_rfm,
  -- Perfil omnichannel
  CASE WHEN canais_utilizados > 1 THEN TRUE ELSE FALSE END    AS cliente_omnichannel
FROM compras_por_cliente;

-- -----------------------------------------------------------
-- VIEW: cac_por_periodo
-- CAC = Investimento em Ads / Novos Clientes no período
-- NOTA: Requer tabela google_ads.campaign_performance (BigQuery Data Transfer)
--       e meta_ads.insights. Estrutura preparada; alimentar após ativar conectores.
-- -----------------------------------------------------------
CREATE OR REPLACE VIEW `retail_gold.view_cac_por_periodo`
OPTIONS(description="Custo de Aquisição de Clientes. REQUER: BigQuery Data Transfer ativo para Google Ads e Meta Ads. Hoje retorna clientes sem custo.")
AS
WITH novos_clientes_mes AS (
  SELECT
    FORMAT_DATE('%Y-%m', data_cadastro) AS ano_mes,
    loja_estado                          AS uf,
    COUNT(DISTINCT cpf_cnpj_hash)        AS novos_clientes
  FROM `retail_gold.view_vendas_360`
  WHERE dias_desde_cadastro <= 30
  GROUP BY 1, 2
),
-- Placeholder: substituir por JOIN real com Google Ads BQ Transfer
-- Estrutura esperada: `google_ads_transfer.campaign_performance`
investimento_ads AS (
  SELECT
    CAST(NULL AS STRING)   AS ano_mes,
    CAST(NULL AS STRING)   AS uf,
    CAST(0.0 AS FLOAT64)   AS investimento_google_ads_r$,
    CAST(0.0 AS FLOAT64)   AS investimento_meta_ads_r$
  WHERE FALSE
)
SELECT
  nc.ano_mes,
  nc.uf,
  nc.novos_clientes,
  COALESCE(ia.investimento_google_ads_r$, 0)   AS investimento_google_ads_r$,
  COALESCE(ia.investimento_meta_ads_r$, 0)     AS investimento_meta_ads_r$,
  COALESCE(ia.investimento_google_ads_r$ + ia.investimento_meta_ads_r$, 0) AS investimento_total_r$,
  ROUND(
    COALESCE(ia.investimento_google_ads_r$ + ia.investimento_meta_ads_r$, 0) /
    NULLIF(nc.novos_clientes, 0),
  2)                                           AS cac_r$,
  -- Alerta: LTV:CAC ideal > 3:1
  'AGUARDANDO_ADS_TRANSFER'                    AS status_cac
FROM novos_clientes_mes nc
LEFT JOIN investimento_ads ia
  ON nc.ano_mes = ia.ano_mes AND nc.uf = ia.uf;

-- -----------------------------------------------------------
-- VIEW: roas_omnichannel
-- ROAS = Receita atribuída / Investimento em Ads
-- Atribuição: cpf_cnpj_hash ↔ GCLID/FBCLID (Server-Side Tagging)
-- -----------------------------------------------------------
CREATE OR REPLACE VIEW `retail_gold.view_roas_omnichannel`
OPTIONS(description="ROAS Omnichannel por canal. Conecta compras físicas (ERP) a cliques digitais via cpf_cnpj_hash. REQUER: Server-Side Tagging com GCLID/FBCLID mapeado ao CPF hash.")
AS
WITH vendas_por_canal AS (
  SELECT
    FORMAT_DATE('%Y-%m', data_venda)  AS ano_mes,
    canal_venda,
    loja_estado                        AS uf,
    COUNT(DISTINCT venda_sk)           AS total_vendas,
    SUM(valor_liquido_item_r$)         AS receita_r$,
    SUM(lucro_item_r$)                 AS lucro_r$,
    COUNT(DISTINCT cpf_cnpj_hash)      AS clientes_unicos,
    AVG(ticket_medio)                  AS ticket_medio_r$
  FROM `retail_gold.view_vendas_360` v
  LEFT JOIN `retail_gold.view_ltv_clientes` ltv USING (cpf_cnpj_hash)
  WHERE status_venda NOT IN ('CANCELADO', 'CANCELADA')
  GROUP BY 1, 2, 3
)
SELECT
  ano_mes,
  canal_venda,
  uf,
  total_vendas,
  receita_r$,
  lucro_r$,
  clientes_unicos,
  ticket_medio_r$,
  -- ROAS será calculado após ativação do BQ Data Transfer
  CAST(NULL AS FLOAT64)              AS investimento_ads_r$,
  CAST(NULL AS FLOAT64)              AS roas,
  CAST(NULL AS FLOAT64)              AS ltv_cac_ratio,
  'AGUARDANDO_ADS_TRANSFER'          AS status_roas
FROM vendas_por_canal
ORDER BY ano_mes DESC, receita_r$ DESC;

-- -----------------------------------------------------------
-- VIEW: kpi_dashboard_diario
-- KPIs executivos consolidados para dashboard
-- -----------------------------------------------------------
CREATE OR REPLACE VIEW `retail_gold.view_kpi_dashboard_diario`
OPTIONS(description="KPIs diários para dashboard executivo. Ticket médio, conversão por canal, crescimento MoM.")
AS
WITH base AS (
  SELECT
    data_venda,
    loja_nome,
    loja_estado,
    canal_venda,
    produto_categoria,
    COUNT(DISTINCT venda_sk)           AS total_vendas,
    COUNT(DISTINCT cpf_cnpj_hash)      AS clientes_atendidos,
    SUM(quantidade)                    AS itens_vendidos,
    SUM(valor_bruto_item_r$)           AS faturamento_bruto_r$,
    SUM(valor_liquido_item_r$)         AS faturamento_liquido_r$,
    SUM(lucro_item_r$)                 AS lucro_r$,
    SUM(desconto_item)                 AS descontos_r$,
    AVG(margem_item_pct)               AS margem_media_pct
  FROM `retail_gold.view_vendas_360`
  WHERE status_venda NOT IN ('CANCELADO', 'CANCELADA')
  GROUP BY 1, 2, 3, 4, 5
)
SELECT
  *,
  ROUND(faturamento_liquido_r$ / NULLIF(total_vendas, 0), 2) AS ticket_medio_r$,
  ROUND(itens_vendidos / NULLIF(total_vendas, 0), 1)         AS itens_por_venda,
  ROUND(descontos_r$ / NULLIF(faturamento_bruto_r$, 0) * 100, 2) AS taxa_desconto_pct
FROM base;
