# WhatsApp Channel Integration

Connect your agent to WhatsApp so users can interact with it from their phones via Twilio.

## Architecture

```
User's Phone (WhatsApp)
    |
    v
Twilio WhatsApp API
    |
    v  (POST /whatsapp/webhook)
FastAPI Server (Cloud Run)
    |
    v
Agent (ADK / LangGraph)
    |
    v  (Twilio REST API)
Twilio WhatsApp API
    |
    v
User's Phone (WhatsApp)
```

## Setup (Step by Step)

### 1. Install Twilio dependency

```bash
uv pip install twilio
# or: pip install "{{cookiecutter.project_name}}[whatsapp]"
```

### 2. Create a Twilio account

1. Go to [twilio.com](https://www.twilio.com/) and sign up (free trial available)
2. From the Console Dashboard, note your **Account SID** and **Auth Token**

### 3. Enable WhatsApp Sandbox (for testing)

1. In the Twilio Console, go to **Messaging > Try it out > Send a WhatsApp message**
2. Follow the instructions to join the sandbox:
   - Send "join <your-sandbox-keyword>" to the Twilio sandbox number from your phone
3. Note the sandbox number (e.g., `whatsapp:+14155238886`)

### 4. Set environment variables

Add these to your `.env` file or deployment configuration:

```bash
# Required: Twilio credentials
TWILIO_ACCOUNT_SID=ACxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
TWILIO_AUTH_TOKEN=your_auth_token_here
TWILIO_WHATSAPP_FROM=whatsapp:+14155238886

# Optional: webhook verification token
WHATSAPP_VERIFY_TOKEN=your_custom_verify_token
```

For **Cloud Run deployment**, add these as secrets via Terraform or `gcloud`:

```bash
# Using gcloud
gcloud run services update YOUR_SERVICE \
  --set-env-vars="TWILIO_WHATSAPP_FROM=whatsapp:+14155238886" \
  --set-secrets="TWILIO_ACCOUNT_SID=twilio-account-sid:latest,TWILIO_AUTH_TOKEN=twilio-auth-token:latest"
```

### 5. Configure the Twilio Webhook

Once your server is deployed, configure Twilio to send messages to your webhook:

1. In the Twilio Console, go to **Messaging > Settings > WhatsApp sandbox settings**
2. Set the webhook URL:
   - **When a message comes in**: `https://YOUR-CLOUD-RUN-URL/whatsapp/webhook`
   - **Method**: POST
3. Save the configuration

### 6. Test it

Send a WhatsApp message to your Twilio sandbox number and you should receive a response from your agent!

## Local Development

For local testing, use [ngrok](https://ngrok.com/) to expose your local server:

```bash
# Start your server
make run

# In another terminal, expose it via ngrok
ngrok http 8000

# Copy the ngrok URL and set it as your Twilio webhook:
# https://xxxx-xxxx.ngrok.io/whatsapp/webhook
```

## Moving to Production

When ready for production:

1. **Get a dedicated WhatsApp number**:
   - Apply for a [Twilio WhatsApp Business Profile](https://www.twilio.com/docs/whatsapp/tutorial/connect-number-business-profile)
   - Register your business phone number with WhatsApp

2. **Update environment variables**:
   - Replace sandbox number with your production number
   - Store credentials in Google Cloud Secret Manager

3. **Configure Terraform** (optional):
   Add to `deployment/terraform/variables.tf`:
   ```hcl
   variable "twilio_account_sid" {
     description = "Twilio Account SID for WhatsApp"
     type        = string
     sensitive   = true
   }
   ```

## API Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/whatsapp/webhook` | POST | Receives incoming WhatsApp messages from Twilio |
| `/whatsapp/webhook` | GET | Webhook verification (for Meta Cloud API compatibility) |
| `/whatsapp/health` | GET | Check WhatsApp channel configuration status |

## Troubleshooting

- **Messages not arriving**: Check that the Twilio webhook URL is correct and accessible
- **No response sent**: Verify `TWILIO_ACCOUNT_SID` and `TWILIO_AUTH_TOKEN` are set correctly
- **"WhatsApp channel not configured"**: Ensure all three required env vars are set
- **Long messages truncated**: WhatsApp has a 1600-char limit; messages are automatically split
