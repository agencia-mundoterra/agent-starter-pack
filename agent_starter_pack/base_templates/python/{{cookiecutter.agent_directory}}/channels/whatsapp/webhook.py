# Copyright 2026 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""WhatsApp webhook handler for receiving and responding to messages via Twilio.

This module provides a FastAPI router that:
1. Receives incoming WhatsApp messages from Twilio webhooks
2. Routes them to the configured agent for processing
3. Sends agent responses back through WhatsApp

Usage:
    Include the router in your FastAPI app and set the agent handler:

        from {{cookiecutter.agent_directory}}.channels.whatsapp import whatsapp_router
        from {{cookiecutter.agent_directory}}.channels.whatsapp.webhook import set_agent_handler

        set_agent_handler(my_agent_function)
        app.include_router(whatsapp_router)
"""

from __future__ import annotations

import hashlib
import hmac
import logging
from collections.abc import Awaitable, Callable
from typing import Annotated

from fastapi import APIRouter, Form, Header, HTTPException, Request, Response

from .client import WhatsAppClient
from .config import WhatsAppConfig

logger = logging.getLogger(__name__)

# Type for the agent handler: takes (user_message, user_id, session_id) -> response text
AgentHandler = Callable[[str, str, str], Awaitable[str]]

# Module-level state
_agent_handler: AgentHandler | None = None
_whatsapp_client: WhatsAppClient | None = None
_config: WhatsAppConfig | None = None

whatsapp_router = APIRouter(prefix="/whatsapp", tags=["whatsapp"])


def set_agent_handler(handler: AgentHandler) -> None:
    """Set the agent handler function that processes incoming messages.

    Args:
        handler: Async function that takes (message, user_id, session_id)
                 and returns the agent's response text.
    """
    global _agent_handler
    _agent_handler = handler


def initialize(config: WhatsAppConfig | None = None) -> None:
    """Initialize the WhatsApp channel with configuration.

    Args:
        config: WhatsApp configuration. If None, loads from environment variables.
    """
    global _whatsapp_client, _config
    _config = config or WhatsAppConfig.from_env()
    if _config.is_configured:
        _whatsapp_client = WhatsAppClient(_config)
        logger.info("WhatsApp channel initialized successfully")
    else:
        logger.warning(
            "WhatsApp channel not fully configured. "
            "Set TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN, and TWILIO_WHATSAPP_FROM."
        )


def _validate_twilio_signature(
    request_url: str, params: dict, signature: str
) -> bool:
    """Validate that the request came from Twilio using X-Twilio-Signature.

    Args:
        request_url: The full URL of the webhook request
        params: The POST parameters from the request
        signature: The X-Twilio-Signature header value

    Returns:
        True if the signature is valid
    """
    if not _config or not _config.auth_token:
        return False

    # Build the data string per Twilio's spec
    data = request_url
    for key in sorted(params.keys()):
        data += key + params[key]

    expected = hmac.new(
        _config.auth_token.encode("utf-8"),
        data.encode("utf-8"),
        hashlib.sha1,
    ).digest()

    import base64

    expected_b64 = base64.b64encode(expected).decode("utf-8")
    return hmac.compare_digest(expected_b64, signature)


def _get_session_id(from_number: str) -> str:
    """Generate a deterministic session ID from the sender's phone number.

    This ensures the same user always gets the same session, maintaining
    conversation continuity across messages.
    """
    return hashlib.sha256(from_number.encode()).hexdigest()[:32]


@whatsapp_router.post("/webhook")
async def receive_message(
    request: Request,
    Body: Annotated[str, Form()] = "",
    From: Annotated[str, Form()] = "",
    To: Annotated[str, Form()] = "",
    MessageSid: Annotated[str, Form()] = "",
    NumMedia: Annotated[str, Form()] = "0",
    x_twilio_signature: Annotated[str | None, Header()] = None,
) -> Response:
    """Receive incoming WhatsApp messages from Twilio webhook.

    Twilio sends POST requests with form data containing the message details.
    This endpoint processes the message, sends it to the agent, and replies.

    Returns:
        TwiML response (empty, since we send replies via the REST API)
    """
    if not _whatsapp_client:
        logger.error("WhatsApp client not initialized")
        raise HTTPException(status_code=503, detail="WhatsApp channel not configured")

    if not _agent_handler:
        logger.error("Agent handler not set")
        raise HTTPException(status_code=503, detail="Agent handler not configured")

    if not From or not Body:
        # Twilio status callbacks or empty messages - acknowledge silently
        return Response(
            content="<Response></Response>",
            media_type="application/xml",
        )

    logger.info(
        "WhatsApp message received from %s: %s (sid: %s)",
        From,
        Body[:50],
        MessageSid,
    )

    # Generate a stable session ID for this user
    user_id = From  # Use phone number as user ID
    session_id = _get_session_id(From)

    try:
        # Invoke the agent
        response_text = await _agent_handler(Body, user_id, session_id)

        # Send the response back via WhatsApp
        _whatsapp_client.send_message(to=From, body=response_text)

    except Exception:
        logger.exception("Error processing WhatsApp message from %s", From)
        _whatsapp_client.send_message(
            to=From,
            body="Desculpe, ocorreu um erro ao processar sua mensagem. Tente novamente.",
        )

    # Return empty TwiML response - we reply via the REST API
    return Response(
        content="<Response></Response>",
        media_type="application/xml",
    )


@whatsapp_router.get("/webhook")
async def verify_webhook(
    hub_mode: str | None = None,
    hub_verify_token: str | None = None,
    hub_challenge: str | None = None,
) -> Response:
    """Handle webhook verification requests.

    Some WhatsApp providers (Meta Cloud API) use GET requests for
    webhook verification. Twilio does not require this, but it's
    included for compatibility.
    """
    if not _config:
        raise HTTPException(status_code=503, detail="WhatsApp channel not configured")

    if hub_mode == "subscribe" and hub_verify_token == _config.verify_token:
        return Response(content=hub_challenge or "", media_type="text/plain")

    raise HTTPException(status_code=403, detail="Verification failed")


@whatsapp_router.get("/health")
async def whatsapp_health() -> dict:
    """Check if the WhatsApp channel is properly configured."""
    return {
        "configured": _config.is_configured if _config else False,
        "agent_handler_set": _agent_handler is not None,
    }
