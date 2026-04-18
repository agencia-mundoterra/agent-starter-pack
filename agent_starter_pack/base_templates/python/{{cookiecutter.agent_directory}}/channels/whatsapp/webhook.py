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

"""Webhook para WhatsApp Cloud API (Meta).

Recebe mensagens via POST, processa com o agente e responde via API da Meta.

Uso:
    from {{cookiecutter.agent_directory}}.channels.whatsapp import whatsapp_router
    from {{cookiecutter.agent_directory}}.channels.whatsapp.webhook import (
        initialize, set_agent_handler
    )

    set_agent_handler(minha_funcao_agente)
    initialize()
    app.include_router(whatsapp_router)
"""

from __future__ import annotations

import hashlib
import logging
from collections.abc import Awaitable, Callable

from fastapi import APIRouter, HTTPException, Query, Request, Response

from .client import WhatsAppClient
from .config import WhatsAppConfig

logger = logging.getLogger(__name__)

# Tipo do handler: recebe (mensagem, user_id, session_id) e retorna texto
AgentHandler = Callable[[str, str, str], Awaitable[str]]

# Estado do modulo
_agent_handler: AgentHandler | None = None
_whatsapp_client: WhatsAppClient | None = None
_config: WhatsAppConfig | None = None

whatsapp_router = APIRouter(prefix="/whatsapp", tags=["whatsapp"])


def set_agent_handler(handler: AgentHandler) -> None:
    """Define a funcao que processa mensagens recebidas.

    Args:
        handler: Funcao async (mensagem, user_id, session_id) -> resposta
    """
    global _agent_handler
    _agent_handler = handler


def initialize(config: WhatsAppConfig | None = None) -> None:
    """Inicializa o canal WhatsApp.

    Args:
        config: Configuracao. Se None, carrega das variaveis de ambiente.
    """
    global _whatsapp_client, _config
    _config = config or WhatsAppConfig.from_env()
    if _config.is_configured:
        _whatsapp_client = WhatsAppClient(_config)
        logger.info("Canal WhatsApp iniciado (Meta Cloud API)")
    else:
        logger.warning(
            "Canal WhatsApp nao configurado. "
            "Defina WHATSAPP_PHONE_NUMBER_ID e WHATSAPP_ACCESS_TOKEN."
        )


def _session_id_for(phone: str) -> str:
    """Gera session ID deterministico a partir do numero de telefone."""
    return hashlib.sha256(phone.encode()).hexdigest()[:32]


# ---------------------------------------------------------------------------
# Verificacao do webhook (GET) - Meta exige este endpoint para ativar o webhook
# ---------------------------------------------------------------------------

@whatsapp_router.get("/webhook")
async def verify_webhook(
    hub_mode: str | None = Query(None, alias="hub.mode"),
    hub_verify_token: str | None = Query(None, alias="hub.verify_token"),
    hub_challenge: str | None = Query(None, alias="hub.challenge"),
) -> Response:
    """Verificacao do webhook pelo Meta for Developers.

    A Meta faz um GET neste endpoint com um desafio. Responda corretamente
    para ativar o webhook.
    """
    if not _config:
        raise HTTPException(status_code=503, detail="Canal nao configurado")

    if hub_mode == "subscribe" and hub_verify_token == _config.verify_token:
        logger.info("Webhook WhatsApp verificado com sucesso")
        return Response(content=hub_challenge or "", media_type="text/plain")

    logger.warning(
        "Falha na verificacao do webhook. Token recebido: %s", hub_verify_token
    )
    raise HTTPException(status_code=403, detail="Token de verificacao invalido")


# ---------------------------------------------------------------------------
# Recepcao de mensagens (POST)
# ---------------------------------------------------------------------------

@whatsapp_router.post("/webhook")
async def receive_message(request: Request) -> dict:
    """Recebe mensagens e eventos do WhatsApp Cloud API da Meta.

    A Meta envia JSON com estrutura aninhada contendo as mensagens.
    Processamos apenas mensagens de texto por enquanto.
    """
    if not _whatsapp_client:
        raise HTTPException(status_code=503, detail="Canal WhatsApp nao configurado")
    if not _agent_handler:
        raise HTTPException(status_code=503, detail="Handler do agente nao definido")

    body = await request.json()

    # Ignora eventos que nao sao do objeto whatsapp_business_account
    if body.get("object") != "whatsapp_business_account":
        return {"status": "ignored"}

    for entry in body.get("entry", []):
        for change in entry.get("changes", []):
            value = change.get("value", {})
            messages = value.get("messages", [])

            for msg in messages:
                await _process_message(msg, value)

    # A Meta espera sempre HTTP 200 para confirmar recebimento
    return {"status": "ok"}


async def _process_message(msg: dict, value: dict) -> None:
    """Processa uma unica mensagem recebida."""
    msg_type = msg.get("type")
    msg_id = msg.get("id", "")
    from_number = msg.get("from", "")

    if not from_number:
        return

    # Extrai o texto conforme o tipo da mensagem
    if msg_type == "text":
        text = msg.get("text", {}).get("body", "").strip()
    elif msg_type == "button":
        # Resposta de botao interativo
        text = msg.get("button", {}).get("text", "").strip()
    else:
        # Tipos nao suportados (audio, imagem, documento, etc.)
        logger.info(
            "Mensagem do tipo '%s' recebida de %s - nao suportada", msg_type, from_number
        )
        await _whatsapp_client.send_message(
            to=from_number,
            body="Desculpe, so consigo responder mensagens de texto por enquanto.",
        )
        return

    if not text:
        return

    logger.info(
        "WhatsApp recebido de %s: %s (id: %s)", from_number, text[:60], msg_id
    )

    # Marca como lida (double check azul)
    if msg_id:
        await _whatsapp_client.mark_as_read(msg_id)

    # Gera IDs de sessao a partir do numero de telefone
    user_id = from_number
    session_id = _session_id_for(from_number)

    try:
        response_text = await _agent_handler(text, user_id, session_id)
        await _whatsapp_client.send_message(to=from_number, body=response_text)
    except Exception:
        logger.exception("Erro ao processar mensagem de %s", from_number)
        await _whatsapp_client.send_message(
            to=from_number,
            body="Ocorreu um erro ao processar sua mensagem. Por favor, tente novamente.",
        )


# ---------------------------------------------------------------------------
# Health check
# ---------------------------------------------------------------------------

@whatsapp_router.get("/health")
async def whatsapp_health() -> dict:
    """Verifica se o canal WhatsApp esta configurado corretamente."""
    return {
        "configured": _config.is_configured if _config else False,
        "agent_handler_set": _agent_handler is not None,
        "provider": "Meta WhatsApp Cloud API",
    }
