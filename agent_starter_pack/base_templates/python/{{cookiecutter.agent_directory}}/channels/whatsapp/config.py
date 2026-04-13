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
    """Configuration for WhatsApp integration via Twilio."""

    # Twilio credentials
    account_sid: str = ""
    auth_token: str = ""
    # The Twilio WhatsApp-enabled phone number (e.g. "whatsapp:+14155238886")
    from_number: str = ""
    # Optional: webhook verification token for security
    verify_token: str = ""

    @classmethod
    def from_env(cls) -> "WhatsAppConfig":
        """Load configuration from environment variables.

        Expected env vars:
            TWILIO_ACCOUNT_SID: Twilio account SID
            TWILIO_AUTH_TOKEN: Twilio auth token
            TWILIO_WHATSAPP_FROM: WhatsApp sender number (e.g. whatsapp:+14155238886)
            WHATSAPP_VERIFY_TOKEN: Optional webhook verification token
        """
        return cls(
            account_sid=os.environ.get("TWILIO_ACCOUNT_SID", ""),
            auth_token=os.environ.get("TWILIO_AUTH_TOKEN", ""),
            from_number=os.environ.get(
                "TWILIO_WHATSAPP_FROM", "whatsapp:+14155238886"
            ),
            verify_token=os.environ.get("WHATSAPP_VERIFY_TOKEN", ""),
        )

    @property
    def is_configured(self) -> bool:
        """Check if all required Twilio credentials are set."""
        return bool(self.account_sid and self.auth_token and self.from_number)
