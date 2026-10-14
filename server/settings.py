"""Deployment settings with errors that never include secret values."""
import base64
import json
import os

from cryptography.fernet import Fernet


def encryption_cipher(value):
    try:
        if not value:
            raise ValueError()
        # Render generates standard Base64; Fernet expects URL-safe Base64.
        decoded = base64.b64decode(value.encode('ascii'), altchars=b'-_', validate=True)
        if len(decoded) != 32:
            raise ValueError()
        return Fernet(base64.urlsafe_b64encode(decoded))
    except (ValueError, TypeError, UnicodeError):
        raise RuntimeError('Configure TOKEN_ENCRYPTION_KEY com uma chave Base64 de 32 bytes.') from None


def firebase_credentials():
    inline = os.environ.get('FIREBASE_SERVICE_ACCOUNT_JSON')
    filename = os.environ.get('GOOGLE_APPLICATION_CREDENTIALS')
    if not inline and not filename:
        return None
    try:
        from firebase_admin import credentials
        if inline:
            data = json.loads(inline)
            if not isinstance(data, dict) or data.get('type') != 'service_account':
                raise ValueError()
            return credentials.Certificate(data)
        return credentials.Certificate(filename)
    except Exception:
        raise RuntimeError('Credenciais Firebase inválidas. Confira o segredo configurado no servidor.') from None
