-- =============================================================
-- BQML - Previsão de Demanda com ARIMA_PLUS
-- Dataset: retail_ml
-- Modelo: forecasting por produto x loja (30 dias à frente)
-- Execução: Semanal (Cloud Scheduler + Dataform)
-- =============================================================

-- -----------------------------------------------------------
-- STEP 1: Série temporal agregada por produto + loja + dia
-- Alimenta o modelo ARIMA_PLUS
-- -----------------------------------------------------------
CREATE OR REPLACE VIEW `retail_ml.vw_serie_temporal_demanda`
OPTIONS(description="Série temporal diária por produto e loja para treinamento ARIMA_PLUS.")
AS
SELECT
  DATE(data_venda)            AS data,
  loja_id,
  loja_nome,
  loja_estado,
  cod_produto,
  produto_nome,
  produto_categoria,
  SUM(quantidade)             AS qt_vendida,
  SUM(valor_liquido_item_r$)  AS receita_r$,
  AVG(preco_unitario)         AS preco_medio_r$
FROM `retail_gold.view_vendas_360`
WHERE
  status_venda NOT IN ('CANCELADO', 'CANCELADA')
  AND data_venda >= DATE_SUB(CURRENT_DATE(), INTERVAL 24 MONTH)
  AND produto_ativo = TRUE
GROUP BY 1, 2, 3, 4, 5, 6, 7;

-- -----------------------------------------------------------
-- STEP 2: Treinar modelo ARIMA_PLUS por produto + loja
-- NOTA: Treinar apenas para SKUs com histórico >= 30 dias
-- -----------------------------------------------------------
CREATE OR REPLACE MODEL `retail_ml.model_demanda_arima`
OPTIONS(
  model_type         = 'ARIMA_PLUS',
  time_series_timestamp_col = 'data',
  time_series_data_col      = 'qt_vendida',
  time_series_id_col        = ['loja_id', 'cod_produto'],
  horizon                   = 30,
  auto_arima                = TRUE,
  data_frequency            = 'DAILY',
  decompose_time_series     = TRUE,
  holiday_region            = 'BR',
  clean_spikes_and_dips     = TRUE
)
AS
SELECT
  data,
  loja_id,
  cod_produto,
  qt_vendida
FROM `retail_ml.vw_serie_temporal_demanda`
WHERE qt_vendida > 0;

-- -----------------------------------------------------------
-- STEP 3: Gerar previsões (executar após treinamento)
-- -----------------------------------------------------------
CREATE OR REPLACE TABLE `retail_ml.previsao_demanda_30d`
PARTITION BY DATE(data_prev)
OPTIONS(description="Previsão de demanda para 30 dias. Atualizar semanalmente.")
AS
SELECT
  forecast_timestamp                   AS data_prev,
  loja_id,
  cod_produto,
  ROUND(forecast_value, 0)             AS qt_prevista,
  ROUND(prediction_interval_lower_bound, 0) AS qt_minima,
  ROUND(prediction_interval_upper_bound, 0) AS qt_maxima,
  ROUND(
    prediction_interval_upper_bound - prediction_interval_lower_bound, 0
  )                                    AS intervalo_confianca,
  -- Enriquecer com info de produto
  dp.produto_nome,
  dp.produto_categoria,
  dp.produto_marca,
  dl.loja_nome,
  dl.loja_estado,
  CURRENT_TIMESTAMP()                  AS dt_previsao_gerada
FROM ML.FORECAST(
  MODEL `retail_ml.model_demanda_arima`,
  STRUCT(30 AS horizon, 0.9 AS confidence_level)
)
LEFT JOIN `retail_silver.dim_produto` dp USING (cod_produto)
LEFT JOIN `retail_silver.dim_loja`    dl USING (loja_id);

-- -----------------------------------------------------------
-- STEP 4: View de alerta de ruptura de estoque
-- Compara previsão de demanda com estoque atual
-- -----------------------------------------------------------
CREATE OR REPLACE VIEW `retail_ml.view_alerta_ruptura_estoque`
OPTIONS(description="Alerta de risco de ruptura de estoque. Cruza previsão de demanda com posição de estoque atual.")
AS
WITH estoque_atual AS (
  SELECT
    loja_id,
    cod_produto,
    SUM(estoque_posicao_venda) AS estoque_posicao,
    MAX(data_venda)            AS ultima_atualizacao
  FROM `retail_gold.view_vendas_360`
  WHERE data_venda >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY)
  GROUP BY 1, 2
),
previsao_proximos_7d AS (
  SELECT
    loja_id,
    cod_produto,
    SUM(qt_prevista) AS demanda_prevista_7d,
    produto_nome,
    produto_categoria,
    loja_nome,
    loja_estado
  FROM `retail_ml.previsao_demanda_30d`
  WHERE data_prev BETWEEN CURRENT_DATE() AND DATE_ADD(CURRENT_DATE(), INTERVAL 7 DAY)
  GROUP BY 1, 2, 5, 6, 7, 8
)
SELECT
  p.loja_id,
  p.loja_nome,
  p.loja_estado,
  p.cod_produto,
  p.produto_nome,
  p.produto_categoria,
  COALESCE(e.estoque_posicao, 0)    AS estoque_atual,
  p.demanda_prevista_7d,
  COALESCE(e.estoque_posicao, 0) - p.demanda_prevista_7d AS saldo_projetado_7d,
  CASE
    WHEN COALESCE(e.estoque_posicao, 0) = 0                          THEN 'RUPTURA'
    WHEN COALESCE(e.estoque_posicao, 0) < p.demanda_prevista_7d      THEN 'CRITICO'
    WHEN COALESCE(e.estoque_posicao, 0) < p.demanda_prevista_7d * 1.5 THEN 'ATENCAO'
    ELSE 'OK'
  END                               AS status_estoque,
  e.ultima_atualizacao
FROM previsao_proximos_7d p
LEFT JOIN estoque_atual e USING (loja_id, cod_produto)
ORDER BY saldo_projetado_7d ASC;

-- -----------------------------------------------------------
-- STEP 5: Embeddings de produto para similaridade (precificação dinâmica)
-- -----------------------------------------------------------
CREATE OR REPLACE MODEL `retail_ml.model_embedding_produto`
OPTIONS(
  model_type     = 'TEXT_EMBEDDING',
  endpoint       = 'text-embedding-005'
)
AS
SELECT
  CONCAT(
    'Produto: ', produto_nome,
    '. Categoria: ', produto_categoria,
    '. Subcategoria: ', COALESCE(produto_subcategoria, ''),
    '. Marca: ', produto_marca,
    '. Cor: ', COALESCE(produto_cor, ''),
    '. Tamanho: ', COALESCE(produto_tamanho, '')
  ) AS content
FROM `retail_silver.dim_produto`
WHERE produto_ativo = TRUE;
