-- =============================================================
-- BRONZE LAYER - Staging Tables (réplica fiel do Supabase)
-- Dataset: retail_bronze
-- Fonte: Supabase PostgreSQL (projeto: emqwecqytddkpwcjybfl)
-- Estratégia: CDC via Google Cloud Datastream
-- IMPORTANTE: Nunca transformar dados aqui. Landing zone pura.
-- =============================================================

-- -----------------------------------------------------------
-- 1. clientes (69.566 linhas, 23 colunas)
-- Chave CDC: updated_at
-- -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS `retail_bronze.clientes` (
  id                BIGINT,
  cod_cliente       INT64,
  loja_id           BIGINT,
  cli_loja          STRING,
  email             STRING,
  cpf_cnpj          STRING,
  nome              STRING,
  sexo              STRING,
  ddd               INT64,
  telefone          STRING,
  data_nascimento   DATE,
  cep               STRING,
  endereco          STRING,
  numero            STRING,
  complemento       STRING,
  bairro            STRING,
  cidade            STRING,
  uf                STRING,
  data_cadastro     TIMESTAMP,
  tipo_cliente      STRING,
  ativo             BOOL,
  created_at        TIMESTAMP,
  updated_at        TIMESTAMP,
  -- Metadados CDC (adicionados pelo Datastream)
  _datastream_metadata JSON OPTIONS(description="Metadados do Datastream CDC (source_timestamp, uuid, etc.)")
)
PARTITION BY DATE(updated_at)
CLUSTER BY loja_id, cpf_cnpj
OPTIONS(
  description="Staging de clientes replicada via CDC do Supabase. Não transformar.",
  require_partition_filter = false
);

-- -----------------------------------------------------------
-- 2. Lojas (12 linhas, 26 colunas)
-- Dimensão pequena - full refresh aceitável
-- ATENÇÃO: PK é codigo_loja (VARCHAR), não id inteiro
-- -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS `retail_bronze.lojas` (
  codigo_loja           STRING,
  descricao             STRING,
  nome_fantasia         STRING,
  cnpj                  BIGINT,
  cnpj_formatado        STRING,
  tabela_precos         BIGINT,
  tipo_loja             STRING,
  estado                STRING,
  email                 STRING,
  area_loja             NUMERIC,
  endereco              STRING,
  numero                BIGINT,
  complemento           STRING,
  bairro                STRING,
  cidade                STRING,
  pais                  STRING,
  ie                    STRING,
  ddd                   NUMERIC,
  telefone              NUMERIC,
  razao_social          STRING,
  cep                   BIGINT,
  inscricao_municipal   STRING,
  codigo_municipio      STRING,
  nro_versao            NUMERIC,
  operacao              STRING,
  perfil                BIGINT,
  _datastream_metadata  JSON
)
OPTIONS(
  description="Cadastro de lojas. PK: codigo_loja (VARCHAR). Atenção: clientes.loja_id é BIGINT - CAST necessário no join."
);

-- -----------------------------------------------------------
-- 3. produtos (8.415 linhas, 15 colunas)
-- Chave CDC: updated_at
-- ATENÇÃO: cod_produto é bpchar (char fixo) - usar TRIM() nos joins
-- -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS `retail_bronze.produtos` (
  id                  BIGINT,
  cod_produto         STRING,
  marca_id            BIGINT,
  ean                 BIGINT,
  nome                STRING,
  categoria           STRING,
  subcategoria        STRING,
  tamanho             STRING,
  cor                 STRING,
  preco_custo         NUMERIC,
  preco_venda         NUMERIC,
  margem_percentual   NUMERIC,
  ativo               BOOL,
  created_at          TIMESTAMP,
  updated_at          TIMESTAMP,
  _datastream_metadata JSON
)
PARTITION BY DATE(updated_at)
CLUSTER BY marca_id, categoria
OPTIONS(
  description="Catálogo de produtos. cod_produto é CHAR(bpchar) - sempre usar TRIM(cod_produto) em JOINs."
);

-- -----------------------------------------------------------
-- 4. marcas (354 linhas, 5 colunas)
-- Dimensão pequena
-- -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS `retail_bronze.marcas` (
  cod_marca          INT64,
  descricao          STRING,
  data_atualizacao   TIMESTAMP,
  ecommerce          INT64,
  ecommerce_ativo    STRING,
  _datastream_metadata JSON
)
OPTIONS(description="Cadastro de marcas. FK: produtos.marca_id -> marcas.cod_marca");

-- -----------------------------------------------------------
-- 5. meios_pagamento (22 linhas, 6 colunas)
-- -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS `retail_bronze.meios_pagamento` (
  id          INT64,
  codigo      INT64,
  descricao   STRING,
  tipo        STRING,
  gateway     STRING,
  created_at  TIMESTAMP,
  _datastream_metadata JSON
)
OPTIONS(description="Meios de pagamento disponíveis.");

-- -----------------------------------------------------------
-- 6. fornecedores (48 linhas, 12 colunas)
-- -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS `retail_bronze.fornecedores` (
  id                INT64,
  nome              STRING,
  avaliacao         STRING,
  prazo_pagamento   STRING,
  markup_medio      NUMERIC,
  desconto_medio    NUMERIC,
  rebate            NUMERIC,
  origem            STRING,
  created_at        TIMESTAMP,
  markup_proposto   NUMERIC,
  status            STRING,
  campanhas         STRING,
  _datastream_metadata JSON
)
OPTIONS(description="Cadastro de fornecedores.");

-- -----------------------------------------------------------
-- 7. funcionarios (119 linhas, 11 colunas)
-- ATENÇÃO: Sem coluna id inteira - PK composta: codigo_loja + controle
-- -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS `retail_bronze.funcionarios` (
  codigo_loja      STRING,
  controle         INT64,
  nome             STRING,
  apelido          STRING,
  cargo            STRING,
  cpf              STRING,
  rg               STRING,
  data_admissao    DATE,
  data_demissao    DATE,
  email            STRING,
  celular          STRING,
  _datastream_metadata JSON
)
OPTIONS(description="Funcionários. PK composta: codigo_loja + controle. Sem coluna id.");

-- -----------------------------------------------------------
-- 8. financeiro (0 linhas - VAZIA, 27 colunas)
-- Preparar estrutura para quando dados forem carregados
-- -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS `retail_bronze.financeiro` (
  id                  BIGINT,
  origem              STRING,
  loja_id             BIGINT,
  vencimento          DATE,
  cliente_id          BIGINT,
  nome_fornecedor     STRING,
  fornecedor_cnpj     STRING,
  cod_planoconta      STRING,
  desc_planoconta     STRING,
  cod_carteira        INT64,
  carteira            STRING,
  cod_situacao        INT64,
  desc_situacao       STRING,
  nf                  INT64,
  valor               NUMERIC,
  saldo               NUMERIC,
  juros               NUMERIC,
  desconto            NUMERIC,
  valor_pago          NUMERIC,
  dt_pagamento        DATE,
  cod_contacorrente   INT64,
  iparcela            INT64,
  modalidade          STRING,
  dt_competencia      DATE,
  observacao          STRING,
  created_at          TIMESTAMP,
  updated_at          TIMESTAMP,
  _datastream_metadata JSON
)
PARTITION BY DATE(updated_at)
CLUSTER BY loja_id, cliente_id
OPTIONS(description="Financeiro - TABELA VAZIA no Supabase. Estrutura preparada para CDC futuro.");

-- -----------------------------------------------------------
-- 9. Vendas_Header (54.601 linhas, 252 colunas)
-- Chave CDC: updated_at
-- JOIN com itens: loja_id + controle + terminal + dt_mov
-- ATENÇÃO: loja_id aqui é VARCHAR (diferente de clientes.loja_id = BIGINT)
-- -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS `retail_bronze.vendas_header` (
  id                    BIGINT,
  controle              BIGINT,
  loja_id               STRING,
  cliente_id            BIGINT,
  data_pedido           DATE,
  hora_pedido           TIME,
  valor_total           NUMERIC,
  desconto_total        NUMERIC,
  valor_liquido         NUMERIC,
  canal_venda           STRING,
  status                STRING,
  created_at            TIMESTAMP,
  updated_at            TIMESTAMP,
  loja                  STRING,
  dt_mov                TIMESTAMP,
  terminal              BIGINT,
  situacao              STRING,
  tipo_doc              STRING,
  coo                   BIGINT,
  ccf                   BIGINT,
  modelo_nf             NUMERIC,
  tipo_nota             STRING,
  serie_nf              NUMERIC,
  numero                BIGINT,
  cnd_pagamento         STRING,
  maior_cfop            STRING,
  prc_desconto          NUMERIC,
  dsc_percentual        NUMERIC,
  dsc_cortesia          NUMERIC,
  acrescimo             NUMERIC,
  valor_total_produtos  NUMERIC,
  valor_total_servicos  NUMERIC,
  frete                 NUMERIC,
  vlr_liquido           NUMERIC,
  icms_base             NUMERIC,
  icms_valor            NUMERIC,
  icms_base_st          NUMERIC,
  icms_valor_st         NUMERIC,
  vendas_brt            NUMERIC,
  devolucoes            NUMERIC,
  fator                 NUMERIC,
  margem2               NUMERIC,
  margem_ind            NUMERIC,
  das_valor             NUMERIC,
  caixa                 INT64,
  gerente               INT64,
  vendedor              INT64,
  obs                   STRING,
  motivo_cancelamento   STRING,
  chave_acesso          STRING,
  nfe_codstatus         BIGINT,
  nfe_motivo            STRING,
  cli_loja              STRING,
  cod_cliente           NUMERIC,
  cpf_consumidor        NUMERIC,
  dt_canc               STRING,
  -- Colunas fiscais/NFe selecionadas (demais disponíveis conforme necessidade)
  pis_valor             NUMERIC,
  cofins_valor          NUMERIC,
  das_aliq              NUMERIC,
  _datastream_metadata  JSON
)
PARTITION BY DATE(dt_mov)
CLUSTER BY loja_id, status, canal_venda
OPTIONS(
  description="Cabeçalho de vendas. 252 colunas originais (subconjunto crítico mantido). JOIN com itens: loja_id+controle+terminal+dt_mov."
);

-- -----------------------------------------------------------
-- 10. vendas_itens (43.936 linhas, 199 colunas)
-- ATENÇÃO: SEM coluna id - PK composta necessária para CDC
-- PK: loja_id + controle + controle_itens + sequencia
-- JOIN com produtos: TRIM(codigo) = TRIM(cod_produto)
-- -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS `retail_bronze.vendas_itens` (
  loja_id             STRING,
  dt_mov              TIMESTAMP,
  controle            BIGINT,
  terminal            BIGINT,
  controle_itens      BIGINT,
  sequencia           BIGINT,
  transacao           STRING,
  codigo              STRING,
  tamanho             BIGINT,
  cor                 BIGINT,
  qt                  BIGINT,
  prc_unitario        NUMERIC,
  dsc_item            NUMERIC,
  dsc_percentual      BIGINT,
  desconto            NUMERIC,
  acrescimo           NUMERIC,
  natureza            STRING,
  total_liquido       NUMERIC,
  situacao            STRING,
  pr_medio            NUMERIC,
  margem              NUMERIC,
  margem2             NUMERIC,
  pr_liquido          NUMERIC,
  icms_valor          NUMERIC,
  ipi_valor           NUMERIC,
  pis_valor           NUMERIC,
  cofins_vlr          NUMERIC,
  das_valor           NUMERIC,
  icms_bc             NUMERIC,
  icms_bc_st          NUMERIC,
  icms_aliq_st        BIGINT,
  icms_vlr_st         NUMERIC,
  estoque_codigo      NUMERIC,
  estoque_posicao     NUMERIC,
  estoque_loja        NUMERIC,
  cod_situacao        NUMERIC,
  valor_venda         NUMERIC,
  data_at             TIMESTAMP,
  descricao_produto   STRING,
  codigo_barras       STRING,
  _datastream_metadata JSON
)
PARTITION BY DATE(dt_mov)
CLUSTER BY loja_id, codigo
OPTIONS(
  description="Itens de venda. SEM id próprio - PK composta: loja_id+controle+controle_itens+sequencia. TRIM(codigo) para JOIN com produtos.cod_produto."
);
