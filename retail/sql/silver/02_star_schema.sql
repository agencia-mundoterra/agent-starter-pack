-- =============================================================
-- SILVER LAYER - Star Schema (Dimensões + Fato)
-- Dataset: retail_silver
-- Fonte: retail_bronze (após deduplicação e tipagem)
-- Execução: Dataform / agendado via Cloud Scheduler
-- =============================================================

-- -----------------------------------------------------------
-- DIM_LOJA
-- Corrige: codigo_loja VARCHAR -> padronizado como STRING
-- -----------------------------------------------------------
CREATE OR REPLACE TABLE `retail_silver.dim_loja`
PARTITION BY RANGE_BUCKET(loja_sk, GENERATE_ARRAY(1, 1000, 1))
CLUSTER BY estado, tipo_loja
OPTIONS(description="Dimensão de Lojas. SK: loja_sk (hash do codigo_loja).")
AS
SELECT
  FARM_FINGERPRINT(codigo_loja)         AS loja_sk,
  TRIM(codigo_loja)                     AS loja_nk,
  descricao,
  COALESCE(nome_fantasia, descricao)    AS nome_fantasia,
  CAST(cnpj AS STRING)                  AS cnpj,
  cnpj_formatado,
  tipo_loja,
  estado,
  cidade,
  bairro,
  endereco,
  CAST(cep AS STRING)                   AS cep,
  area_loja,
  email,
  CAST(ddd AS INT64)                    AS ddd,
  CAST(telefone AS INT64)               AS telefone,
  razao_social,
  inscricao_municipal,
  codigo_municipio,
  perfil
FROM `retail_bronze.lojas`
QUALIFY ROW_NUMBER() OVER (PARTITION BY codigo_loja ORDER BY nro_versao DESC) = 1;

-- -----------------------------------------------------------
-- DIM_CLIENTE
-- Corrige: loja_id BIGINT -> JOIN com dim_loja via CAST(loja_id AS STRING)
-- Segurança: cpf_cnpj hasheado para joins com campanhas
-- -----------------------------------------------------------
CREATE OR REPLACE TABLE `retail_silver.dim_cliente`
PARTITION BY DATE(data_cadastro)
CLUSTER BY uf, tipo_cliente
OPTIONS(description="Dimensão de Clientes. cpf_cnpj_hash permite join seguro com campanhas digitais.")
AS
SELECT
  c.id                                              AS cliente_sk,
  c.cod_cliente,
  c.cli_loja,
  FARM_FINGERPRINT(TRIM(c.loja_id::STRING))        AS loja_sk,
  LOWER(TRIM(c.email))                             AS email,
  TO_HEX(MD5(REGEXP_REPLACE(c.cpf_cnpj, r'[^0-9]', ''))) AS cpf_cnpj_hash,
  c.nome,
  c.sexo,
  c.ddd,
  c.telefone,
  c.data_nascimento,
  DATE_DIFF(CURRENT_DATE(), c.data_nascimento, YEAR) AS idade,
  c.cep,
  c.cidade,
  c.uf,
  c.bairro,
  CAST(c.data_cadastro AS DATE)                    AS data_cadastro,
  c.tipo_cliente,
  c.ativo,
  c.created_at,
  c.updated_at
FROM `retail_bronze.clientes` c
QUALIFY ROW_NUMBER() OVER (PARTITION BY c.id ORDER BY c.updated_at DESC) = 1;

-- -----------------------------------------------------------
-- DIM_MARCA
-- -----------------------------------------------------------
CREATE OR REPLACE TABLE `retail_silver.dim_marca`
OPTIONS(description="Dimensão de Marcas.")
AS
SELECT
  cod_marca         AS marca_sk,
  descricao         AS marca,
  ecommerce_ativo   AS ativa_ecommerce,
  data_atualizacao
FROM `retail_bronze.marcas`
QUALIFY ROW_NUMBER() OVER (PARTITION BY cod_marca ORDER BY data_atualizacao DESC) = 1;

-- -----------------------------------------------------------
-- DIM_PRODUTO
-- Corrige: TRIM(cod_produto) - bpchar padding
-- Join com marcas via marca_id -> cod_marca
-- -----------------------------------------------------------
CREATE OR REPLACE TABLE `retail_silver.dim_produto`
CLUSTER BY categoria, subcategoria, marca_sk
OPTIONS(description="Dimensão de Produtos. Sempre usar TRIM(cod_produto) para JOINs.")
AS
SELECT
  p.id                                  AS produto_sk,
  TRIM(p.cod_produto)                   AS cod_produto,
  p.marca_id                            AS marca_sk,
  m.descricao                           AS marca,
  p.ean,
  p.nome,
  p.categoria,
  p.subcategoria,
  p.tamanho,
  p.cor,
  p.preco_custo,
  p.preco_venda,
  ROUND(p.preco_venda - p.preco_custo, 2) AS margem_absoluta,
  p.margem_percentual,
  p.ativo,
  p.created_at,
  p.updated_at
FROM `retail_bronze.produtos` p
LEFT JOIN `retail_bronze.marcas` m ON p.marca_id = m.cod_marca
QUALIFY ROW_NUMBER() OVER (PARTITION BY p.id ORDER BY p.updated_at DESC) = 1;

-- -----------------------------------------------------------
-- DIM_MEIO_PAGAMENTO
-- -----------------------------------------------------------
CREATE OR REPLACE TABLE `retail_silver.dim_meio_pagamento`
OPTIONS(description="Meios de pagamento disponíveis.")
AS
SELECT
  id    AS meio_pagamento_sk,
  codigo,
  descricao,
  tipo,
  gateway
FROM `retail_bronze.meios_pagamento`;

-- -----------------------------------------------------------
-- DIM_FUNCIONARIO
-- Corrige: PK composta codigo_loja + controle
-- -----------------------------------------------------------
CREATE OR REPLACE TABLE `retail_silver.dim_funcionario`
CLUSTER BY codigo_loja, cargo
OPTIONS(description="Funcionários. PK composta: codigo_loja + controle.")
AS
SELECT
  FARM_FINGERPRINT(CONCAT(codigo_loja, CAST(controle AS STRING))) AS funcionario_sk,
  codigo_loja,
  controle,
  nome,
  apelido,
  cargo,
  TO_HEX(MD5(cpf))  AS cpf_hash,
  data_admissao,
  data_demissao,
  CASE WHEN data_demissao IS NULL THEN TRUE ELSE FALSE END AS ativo,
  email,
  celular
FROM `retail_bronze.funcionarios`;

-- -----------------------------------------------------------
-- DIM_TEMPO
-- Gerada para range de datas do histórico de vendas
-- -----------------------------------------------------------
CREATE OR REPLACE TABLE `retail_silver.dim_tempo`
OPTIONS(description="Dimensão de tempo gerada. Cobre 2020-2030.")
AS
SELECT
  FORMAT_DATE('%Y%m%d', d)   AS tempo_sk,
  d                          AS data,
  EXTRACT(YEAR FROM d)       AS ano,
  EXTRACT(QUARTER FROM d)    AS trimestre,
  EXTRACT(MONTH FROM d)      AS mes,
  FORMAT_DATE('%B', d)       AS nome_mes,
  EXTRACT(WEEK FROM d)       AS semana_ano,
  EXTRACT(DAYOFWEEK FROM d)  AS dia_semana,
  FORMAT_DATE('%A', d)       AS nome_dia_semana,
  EXTRACT(DAY FROM d)        AS dia,
  CASE WHEN EXTRACT(DAYOFWEEK FROM d) IN (1, 7) THEN TRUE ELSE FALSE END AS fim_de_semana
FROM UNNEST(GENERATE_DATE_ARRAY('2020-01-01', '2030-12-31')) AS d;

-- -----------------------------------------------------------
-- FACT_VENDAS
-- Granularidade: 1 linha por item vendido (vendas_itens)
-- JOIN crítico: loja_id + controle + terminal + dt_mov
-- JOIN produto: TRIM(vi.codigo) = TRIM(p.cod_produto)
-- ATENÇÃO: vendas_header.loja_id é VARCHAR, clientes.loja_id é BIGINT
-- -----------------------------------------------------------
CREATE OR REPLACE TABLE `retail_silver.fact_vendas`
PARTITION BY DATE(dt_mov)
CLUSTER BY loja_sk, produto_sk, canal_venda
OPTIONS(description="Fato de Vendas. Granularidade: item. Particionado por dt_mov, clusterizado por loja+produto+canal.")
AS
WITH
-- Pegar header deduplicado
header AS (
  SELECT *
  FROM `retail_bronze.vendas_header`
  WHERE situacao NOT IN ('CANCELADO', 'CANCELADA')
     OR situacao IS NULL
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY loja_id, controle, terminal
    ORDER BY updated_at DESC
  ) = 1
),
-- Pegar itens deduplicados (PK composta)
itens AS (
  SELECT *
  FROM `retail_bronze.vendas_itens`
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY loja_id, controle, controle_itens, sequencia
    ORDER BY data_at DESC
  ) = 1
),
-- Produto lookup com TRIM para resolver bpchar padding
produto_lookup AS (
  SELECT
    TRIM(cod_produto)  AS cod_produto_norm,
    id                 AS produto_sk,
    categoria,
    subcategoria,
    marca_sk,
    preco_custo
  FROM `retail_silver.dim_produto`
),
-- Loja lookup: CAST codigo_loja para FARM_FINGERPRINT
loja_lookup AS (
  SELECT loja_sk, loja_nk
  FROM `retail_silver.dim_loja`
)
SELECT
  -- Chaves surrogate
  FARM_FINGERPRINT(CONCAT(
    h.loja_id, CAST(h.controle AS STRING),
    CAST(i.controle_itens AS STRING), CAST(i.sequencia AS STRING)
  ))                                                AS venda_item_sk,
  h.id                                              AS venda_sk,
  COALESCE(p.produto_sk, -1)                        AS produto_sk,
  COALESCE(l.loja_sk, FARM_FINGERPRINT(h.loja_id)) AS loja_sk,
  COALESCE(h.cliente_id, -1)                        AS cliente_sk,
  FORMAT_DATE('%Y%m%d', DATE(h.dt_mov))             AS tempo_sk,
  COALESCE(h.vendedor, -1)                          AS vendedor_sk,

  -- Chaves naturais para rastreabilidade
  h.loja_id,
  h.controle,
  h.terminal,
  DATE(h.dt_mov)              AS dt_mov,
  h.data_pedido,
  i.controle_itens,
  i.sequencia,
  TRIM(i.codigo)              AS cod_produto,
  i.transacao,

  -- Métricas do item
  i.qt                        AS quantidade,
  i.prc_unitario              AS preco_unitario,
  i.desconto                  AS desconto_item,
  i.acrescimo                 AS acrescimo_item,
  i.total_liquido             AS valor_liquido_item,
  i.valor_venda               AS valor_bruto_item,
  COALESCE(p.preco_custo, i.pr_medio) AS custo_unitario,
  i.pr_liquido                AS preco_liquido,
  i.margem                    AS margem_percentual,

  -- Estoque (rastreado em itens)
  i.estoque_codigo,
  i.estoque_posicao,
  i.estoque_loja,

  -- Contexto da venda
  h.canal_venda,
  h.status,
  h.situacao,
  h.tipo_doc,
  h.cnd_pagamento,
  h.gerente,
  h.vendedor,
  h.caixa,

  -- Métricas do header (proporcionais ao item)
  h.valor_total               AS valor_total_venda,
  h.desconto_total            AS desconto_total_venda,
  h.valor_liquido             AS valor_liquido_venda,
  h.frete,

  -- Fiscal (resumo)
  i.icms_valor,
  i.pis_valor,
  i.cofins_vlr,
  i.das_valor,

  -- Metadados
  h.created_at,
  h.updated_at

FROM itens i
JOIN header h
  ON i.loja_id  = h.loja_id
 AND i.controle = h.controle
 AND i.terminal = h.terminal
LEFT JOIN produto_lookup p
  ON TRIM(i.codigo) = p.cod_produto_norm
LEFT JOIN loja_lookup l
  ON i.loja_id = l.loja_nk;
