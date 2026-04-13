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

import logging

from twilio.rest import Client

from .config import WhatsAppConfig

logger = logging.getLogger(__name__)

# WhatsApp has a 1600-character limit per message
WHATSAPP_MAX_LENGTH = 1600


class WhatsAppClient:
    """Client for sending messages via Twilio WhatsApp API."""

    def __init__(self, config: WhatsAppConfig) -> None:
        self.config = config
        self._client = Client(config.account_sid, config.auth_token)

    def send_message(self, to: str, body: str) -> str | None:
        """Send a WhatsApp message.

        Args:
            to: Recipient phone number in WhatsApp format (e.g. "whatsapp:+5511999999999")
            body: Message text content

        Returns:
            Message SID if successful, None on failure
        """
        try:
            # Split long messages to respect WhatsApp limits
            chunks = self._split_message(body)
            last_sid = None
            for chunk in chunks:
                message = self._client.messages.create(
                    from_=self.config.from_number,
                    to=to,
                    body=chunk,
                )
                last_sid = message.sid
                logger.info("WhatsApp message sent: %s -> %s", last_sid, to)
            return last_sid
        except Exception:
            logger.exception("Failed to send WhatsApp message to %s", to)
            return None

    def send_media(self, to: str, body: str, media_url: str) -> str | None:
        """Send a WhatsApp message with media attachment.

        Args:
            to: Recipient phone number in WhatsApp format
            body: Caption text
            media_url: Public URL of the media to send

        Returns:
            Message SID if successful, None on failure
        """
        try:
            message = self._client.messages.create(
                from_=self.config.from_number,
                to=to,
                body=body,
                media_url=[media_url],
            )
            logger.info("WhatsApp media sent: %s -> %s", message.sid, to)
            return message.sid
        except Exception:
            logger.exception("Failed to send WhatsApp media to %s", to)
            return None

    @staticmethod
    def _split_message(text: str) -> list[str]:
        """Split a long message into chunks that fit WhatsApp's limit.

        Splits on paragraph boundaries when possible, falling back to
        sentence boundaries, then hard truncation.
        """
        if len(text) <= WHATSAPP_MAX_LENGTH:
            return [text]

        chunks: list[str] = []
        remaining = text
        while remaining:
            if len(remaining) <= WHATSAPP_MAX_LENGTH:
                chunks.append(remaining)
                break

            # Try to split at paragraph boundary
            cut = remaining[:WHATSAPP_MAX_LENGTH].rfind("\n\n")
            if cut <= 0:
                # Try sentence boundary
                cut = remaining[:WHATSAPP_MAX_LENGTH].rfind(". ")
                if cut <= 0:
                    # Hard cut at limit
                    cut = WHATSAPP_MAX_LENGTH - 1
                else:
                    cut += 1  # Include the period

            chunks.append(remaining[:cut].rstrip())
            remaining = remaining[cut:].lstrip()

        return chunks
