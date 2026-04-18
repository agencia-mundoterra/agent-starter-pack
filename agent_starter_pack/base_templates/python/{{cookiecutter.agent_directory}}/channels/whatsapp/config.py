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

import os

from pydantic import BaseModel


class WhatsAppConfig(BaseModel):
    """Configuracao para integracao com WhatsApp Cloud API (Meta)."""

    # ID do numero de telefone no Meta for Developers
    phone_number_id: str = ""
    # Token de acesso permanente da Meta
    access_token: str = ""
    # Token de verificacao do webhook (voce escolhe este valor)
    verify_token: str = ""
    # Versao da Graph API
    api_version: str = "v19.0"

    @classmethod
    def from_env(cls) -> "WhatsAppConfig":
        """Carrega configuracao a partir das variaveis de ambiente.

        Variaveis esperadas:
            WHATSAPP_PHONE_NUMBER_ID : Phone Number ID do Meta for Developers
            WHATSAPP_ACCESS_TOKEN    : Token de acesso permanente
            WHATSAPP_VERIFY_TOKEN    : Token de verificacao do webhook
        """
        return cls(
            phone_number_id=os.environ.get("WHATSAPP_PHONE_NUMBER_ID", ""),
            access_token=os.environ.get("WHATSAPP_ACCESS_TOKEN", ""),
            verify_token=os.environ.get("WHATSAPP_VERIFY_TOKEN", "meu_token_secreto"),
        )

    @property
    def is_configured(self) -> bool:
        """Retorna True se as credenciais obrigatorias estao definidas."""
        return bool(self.phone_number_id and self.access_token)

    @property
    def messages_url(self) -> str:
        """URL da API de envio de mensagens da Meta."""
        return (
            f"https://graph.facebook.com/{self.api_version}"
            f"/{self.phone_number_id}/messages"
        )
