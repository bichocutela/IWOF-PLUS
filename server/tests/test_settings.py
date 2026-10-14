import base64
import pytest
from cryptography.fernet import Fernet
from settings import encryption_cipher, firebase_credentials


def test_render_and_fernet_keys_encrypt_the_same_data():
    raw = bytes(range(32))
    standard = base64.b64encode(raw).decode()
    urlsafe = base64.urlsafe_b64encode(raw).decode()
    encrypted = encryption_cipher(standard).encrypt(b'session')
    assert encryption_cipher(urlsafe).decrypt(encrypted) == b'session'


@pytest.mark.parametrize('value', [None, '', 'private-secret-invalid', 'é', base64.b64encode(b'short').decode()])
def test_bad_encryption_key_has_safe_error(value):
    with pytest.raises(RuntimeError) as error:
        encryption_cipher(value)
    assert 'private-secret-invalid' not in str(error.value)


def test_firebase_is_optional(monkeypatch):
    monkeypatch.delenv('FIREBASE_SERVICE_ACCOUNT_JSON', raising=False)
    monkeypatch.delenv('GOOGLE_APPLICATION_CREDENTIALS', raising=False)
    assert firebase_credentials() is None


def test_bad_firebase_secret_is_not_echoed(monkeypatch):
    monkeypatch.setenv('FIREBASE_SERVICE_ACCOUNT_JSON', 'private-secret-invalid')
    with pytest.raises(RuntimeError) as error:
        firebase_credentials()
    assert 'private-secret-invalid' not in str(error.value)


def test_inline_firebase_credentials_take_priority(monkeypatch):
    from firebase_admin import credentials
    monkeypatch.setenv('FIREBASE_SERVICE_ACCOUNT_JSON', '{"type":"service_account","project_id":"test"}')
    monkeypatch.setenv('GOOGLE_APPLICATION_CREDENTIALS', '/nonexistent/file')
    monkeypatch.setattr(credentials, 'Certificate', lambda data: data)
    assert firebase_credentials()['project_id'] == 'test'
