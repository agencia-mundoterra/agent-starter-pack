-- =============================================================
-- GOLD LAYER - OBT (One Big Table) para Gemini Enterprise
-- Dataset: retail_gold
-- Propósito: View flat sem JOINs para o Gemini gerar SQL preciso
-- Metadados semânticos via OPTIONS(description) em cada coluna
-- =============================================================

CREATE OR REPLACE VIEW `retail_gold.view_vendas_360`
OPTIONS(
  description="View flat omnichannel 360. Combina Vendas + Cliente + Produto + Loja + Funcionário. Gemini-ready: sem JOINs necessários. Granularidade: 1 linha por item vendido."
)
AS
SELECT
  -- ---- VENDA HEADER ----
  fv.venda_item_sk,
  fv.venda_sk,
  fv.loja_id                                    AS venda_loja_id,
  fv.controle                                   AS venda_controle,
  fv.dt_mov                                     AS data_venda,
  fv.data_pedido,
  fv.canal_venda,
  fv.status                                     AS status_venda,
  fv.situacao                                   AS situacao_venda,
  fv.tipo_doc,
  fv.cnd_pagamento,

  -- ---- ITEM DA VENDA ----
  fv.controle_itens,
  fv.sequencia,
  fv.cod_produto,
  fv.quantidade,
  fv.preco_unitario,
  fv.desconto_item,
  fv.valor_liquido_item                         AS valor_liquido_item_r$,
  fv.valor_bruto_item                           AS valor_bruto_item_r$,
  fv.custo_unitario,
  ROUND(fv.valor_liquido_item - (fv.custo_unitario * fv.quantidade), 2) AS lucro_item_r$,
  fv.margem_percentual                          AS margem_item_pct,

  -- ---- PRODUTO ----
  dp.nome                                       AS produto_nome,
  dp.categoria                                  AS produto_categoria,
  dp.subcategoria                               AS produto_subcategoria,
  dp.tamanho                                    AS produto_tamanho,
  dp.cor                                        AS produto_cor,
  dp.marca                                      AS produto_marca,
  dp.ean                                        AS produto_ean,
  dp.preco_venda                                AS produto_preco_tabela,
  dp.preco_custo                                AS produto_custo,
  dp.margem_percentual                          AS produto_margem_cadastro_pct,
  dp.ativo                                      AS produto_ativo,

  -- ---- LOJA ----
  dl.nome_fantasia                              AS loja_nome,
  dl.tipo_loja,
  dl.cidade                                     AS loja_cidade,
  dl.estado                                     AS loja_estado,
  dl.area_loja                                  AS loja_area_m2,

  -- ---- CLIENTE ----
  dc.nome                                       AS cliente_nome,
  dc.email                                      AS cliente_email,
  dc.cpf_cnpj_hash,
  dc.sexo                                       AS cliente_sexo,
  dc.idade                                      AS cliente_idade,
  dc.cidade                                     AS cliente_cidade,
  dc.uf                                         AS cliente_uf,
  dc.tipo_cliente,
  dc.data_cadastro                              AS cliente_data_cadastro,
  DATE_DIFF(fv.dt_mov, dc.data_cadastro, DAY)  AS dias_desde_cadastro,

  -- ---- FUNCIONÁRIO (VENDEDOR) ----
  df.nome                                       AS vendedor_nome,
  df.cargo                                      AS vendedor_cargo,
  df.codigo_loja                                AS vendedor_loja,

  -- ---- TEMPO ----
  dt.ano,
  dt.trimestre,
  dt.mes,
  dt.nome_mes,
  dt.semana_ano,
  dt.nome_dia_semana,
  dt.fim_de_semana,

  -- ---- FISCAL (RESUMO) ----
  fv.icms_valor,
  fv.pis_valor,
  fv.cofins_vlr,
  fv.das_valor,

  -- ---- ESTOQUE (POSIÇÃO NO MOMENTO DA VENDA) ----
  fv.estoque_codigo,
  fv.estoque_posicao                            AS estoque_posicao_venda,
  fv.estoque_loja

FROM `retail_silver.fact_vendas` fv
LEFT JOIN `retail_silver.dim_produto`     dp ON fv.produto_sk  = dp.produto_sk
LEFT JOIN `retail_silver.dim_loja`        dl ON fv.loja_sk     = dl.loja_sk
LEFT JOIN `retail_silver.dim_cliente`     dc ON fv.cliente_sk  = dc.cliente_sk
LEFT JOIN `retail_silver.dim_funcionario` df ON fv.vendedor_sk = df.funcionario_sk
LEFT JOIN `retail_silver.dim_tempo`       dt ON fv.tempo_sk    = dt.tempo_sk;
