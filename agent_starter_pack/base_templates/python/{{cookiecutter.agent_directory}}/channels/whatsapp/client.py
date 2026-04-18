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

"""Cliente para enviar mensagens via WhatsApp Cloud API (Meta)."""

import logging

import httpx

from .config import WhatsAppConfig

logger = logging.getLogger(__name__)

# WhatsApp limita mensagens de texto a 4096 caracteres
WHATSAPP_MAX_LENGTH = 4096


class WhatsAppClient:
    """Envia mensagens pelo WhatsApp Cloud API da Meta (sem Twilio)."""

    def __init__(self, config: WhatsAppConfig) -> None:
        self.config = config
        self._headers = {
            "Authorization": f"Bearer {config.access_token}",
            "Content-Type": "application/json",
        }

    async def send_message(self, to: str, body: str) -> bool:
        """Envia uma mensagem de texto para um numero WhatsApp.

        Args:
            to: Numero do destinatario no formato internacional (ex: 5511999999999)
            body: Texto da mensagem

        Returns:
            True se enviado com sucesso
        """
        chunks = self._split_message(body)
        success = True
        async with httpx.AsyncClient(timeout=10.0) as client:
            for chunk in chunks:
                payload = {
                    "messaging_product": "whatsapp",
                    "recipient_type": "individual",
                    "to": to,
                    "type": "text",
                    "text": {"preview_url": False, "body": chunk},
                }
                try:
                    resp = await client.post(
                        self.config.messages_url,
                        headers=self._headers,
                        json=payload,
                    )
                    resp.raise_for_status()
                    logger.info("Mensagem WhatsApp enviada para %s", to)
                except httpx.HTTPStatusError as e:
                    logger.error(
                        "Erro ao enviar WhatsApp para %s: %s - %s",
                        to,
                        e.response.status_code,
                        e.response.text,
                    )
                    success = False
                except Exception:
                    logger.exception("Falha ao enviar WhatsApp para %s", to)
                    success = False
        return success

    async def mark_as_read(self, message_id: str) -> None:
        """Marca uma mensagem recebida como lida (double check azul).

        Args:
            message_id: ID da mensagem recebida
        """
        payload = {
            "messaging_product": "whatsapp",
            "status": "read",
            "message_id": message_id,
        }
        async with httpx.AsyncClient(timeout=5.0) as client:
            try:
                resp = await client.post(
                    self.config.messages_url,
                    headers=self._headers,
                    json=payload,
                )
                resp.raise_for_status()
            except Exception:
                logger.warning("Nao foi possivel marcar mensagem %s como lida", message_id)

    @staticmethod
    def _split_message(text: str) -> list[str]:
        """Divide mensagens longas respeitando o limite de 4096 caracteres."""
        if len(text) <= WHATSAPP_MAX_LENGTH:
            return [text]

        chunks: list[str] = []
        remaining = text
        while remaining:
            if len(remaining) <= WHATSAPP_MAX_LENGTH:
                chunks.append(remaining)
                break
            # Tenta quebrar em paragrafo
            cut = remaining[:WHATSAPP_MAX_LENGTH].rfind("\n\n")
            if cut <= 0:
                # Tenta quebrar em frase
                cut = remaining[:WHATSAPP_MAX_LENGTH].rfind(". ")
                if cut <= 0:
                    cut = WHATSAPP_MAX_LENGTH - 1
                else:
                    cut += 1
            chunks.append(remaining[:cut].rstrip())
            remaining = remaining[cut:].lstrip()
        return chunks
