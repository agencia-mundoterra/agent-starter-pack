# Canal WhatsApp (Meta WhatsApp Cloud API)

Conecta seu agente ao WhatsApp usando a API oficial da Meta — **sem Twilio, sem intermediarios**.

## Como funciona

```
Seu celular (WhatsApp)
    |
    v
Meta WhatsApp Cloud API
    |
    v  POST /whatsapp/webhook
FastAPI Server (Cloud Run)
    |
    v
Agente (ADK / LangGraph)
    |
    v  Graph API REST
Meta WhatsApp Cloud API
    |
    v
Seu celular (WhatsApp)
```

---

## Configuracao Passo a Passo

### 1. Criar conta no Meta for Developers

1. Acesse [developers.facebook.com](https://developers.facebook.com/)
2. Clique em **Meus Apps > Criar App**
3. Escolha o tipo **Business**
4. Adicione o produto **WhatsApp** ao seu app

### 2. Obter credenciais

No painel do seu app no Meta for Developers:

1. Va em **WhatsApp > Configuracao da API**
2. Anote:
   - **Phone Number ID** (ex: `123456789012345`)
   - **Token de Acesso** — use um token permanente (System User) para producao

> Para criar um token permanente:  
> Business Settings > System Users > Criar > Gerar Token > selecionar o app

### 3. Configurar variaveis de ambiente

```bash
# Obrigatorios
WHATSAPP_PHONE_NUMBER_ID=123456789012345
WHATSAPP_ACCESS_TOKEN=EAAxxxxxxxxxxxxxxxx

# Voce escolhe este valor (qualquer texto secreto)
WHATSAPP_VERIFY_TOKEN=meu_token_secreto_123
```

Para **Cloud Run**, adicione via Secret Manager:

```bash
gcloud run services update SEU_SERVICE \
  --set-env-vars="WHATSAPP_PHONE_NUMBER_ID=123456789012345,WHATSAPP_VERIFY_TOKEN=meu_token_secreto_123" \
  --set-secrets="WHATSAPP_ACCESS_TOKEN=whatsapp-token:latest"
```

### 4. Instalar dependencia

```bash
pip install httpx
# ou: pip install "seu-projeto[whatsapp]"
```

### 5. Registrar o webhook no Meta

Voce precisa de uma URL publica (Cloud Run, ngrok para testes).

1. No painel Meta, va em **WhatsApp > Configuracao**
2. Em **Webhooks**, clique em **Configurar**:
   - **URL do Callback**: `https://SEU-URL/whatsapp/webhook`
   - **Token de Verificacao**: o mesmo valor de `WHATSAPP_VERIFY_TOKEN`
3. Clique em **Verificar e salvar**
4. Inscreva-se no campo **messages**

### 6. Testar

Envie uma mensagem WhatsApp para o numero cadastrado no Meta e aguarde a resposta do agente!

---

## Teste local com ngrok

```bash
# Terminal 1: iniciar servidor
make run

# Terminal 2: expor localmente
ngrok http 8000

# Copie a URL do ngrok (ex: https://xxxx.ngrok.io)
# Use como webhook: https://xxxx.ngrok.io/whatsapp/webhook
```

---

## Endpoints

| Endpoint | Metodo | Descricao |
|----------|--------|-----------|
| `/whatsapp/webhook` | GET | Verificacao do webhook pela Meta |
| `/whatsapp/webhook` | POST | Recebe mensagens do WhatsApp |
| `/whatsapp/health` | GET | Status do canal |

---

## Solucao de problemas

| Problema | Solucao |
|----------|---------|
| Webhook nao verifica | Confira se `WHATSAPP_VERIFY_TOKEN` bate com o configurado na Meta |
| Mensagens nao chegam | Assegure que inscreveu no campo `messages` no painel Meta |
| Erro 401 | `WHATSAPP_ACCESS_TOKEN` invalido ou expirado |
| Sem resposta | Verifique `WHATSAPP_PHONE_NUMBER_ID` |
| Canal desabilitado | `WHATSAPP_PHONE_NUMBER_ID` nao esta definido |
