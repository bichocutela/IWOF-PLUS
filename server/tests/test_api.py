import asyncio
import pytest
from fastapi import HTTPException
import app


def test_invalid_session_cannot_register_device():
    with pytest.raises(HTTPException) as error:
        asyncio.run(app.verify_session('invalid-token'))
    assert error.value.status_code == 401


def test_upstream_identity_must_match_token_hint(monkeypatch):
    import base64
    token = 'header.' + base64.urlsafe_b64encode(b'{"id":"7"}').decode().strip('=') + '.signature'
    async def wrong_identity(*args):
        return {'worker': {'id': '8'}}
    monkeypatch.setattr(app, 'graphql', wrong_identity)
    with pytest.raises(HTTPException) as error:
        asyncio.run(app.verify_session(token))
    assert error.value.status_code == 401


def test_paginated_fetch_checks_completeness(monkeypatch):
    calls = []
    async def page(*args):
        calls.append(args)
        return {'workerRequestsNewApp': {'totalResults': 2, 'requests': [{'id': str(len(calls))}]}}
    monkeypatch.setattr(app, 'graphql', page)
    jobs = asyncio.run(app.all_jobs('test-token', 'Natal'))
    assert [row['id'] for row in jobs] == ['1', '2']
    assert '"Natal"' in calls[0][1]


def test_empty_page_does_not_commit_an_incomplete_baseline(monkeypatch):
    async def empty(*args):
        return {'workerRequestsNewApp': {'totalResults': 3, 'requests': []}}
    monkeypatch.setattr(app, 'graphql', empty)
    with pytest.raises(app.UpstreamError):
        asyncio.run(app.all_jobs('test-token', 'Natal'))


def test_device_registration_encrypts_session_and_requires_device_secret(tmp_path, monkeypatch):
    from cryptography.fernet import Fernet
    from fastapi.testclient import TestClient
    monkeypatch.setenv('TOKEN_ENCRYPTION_KEY', Fernet.generate_key().decode())
    monkeypatch.setenv('DATABASE_PATH', str(tmp_path / 'api.sqlite'))
    monkeypatch.delenv('GOOGLE_APPLICATION_CREDENTIALS', raising=False)
    async def identity(token):
        return '7'
    async def no_jobs(*args):
        return []
    monkeypatch.setattr(app, 'verify_session', identity)
    monkeypatch.setattr(app, 'all_jobs', no_jobs)
    with TestClient(app.app) as client:
        payload = {'session': 'legitimate-test-session', 'push_token': 'test-device-push-token', 'city': 'Natal'}
        response = client.post('/devices', json=payload)
        assert response.status_code == 200
        secret = response.json()['secret']
        assert secret and not response.json()['push_ready']
        assert client.get('/devices/me').status_code == 401
        headers = {'authorization': 'Bearer ' + secret}
        assert client.get('/devices/me', headers=headers).json()['city'] == 'Natal'
        with app.store.connection() as db:
            stored = db.execute('SELECT session FROM devices').fetchone()['session']
        assert stored != payload['session']
        assert app.cipher.decrypt(stored.encode()).decode() == payload['session']
        assert client.delete('/devices/me', headers=headers).status_code == 200
        assert client.get('/devices/me', headers=headers).status_code == 401


def test_another_account_cannot_replace_registered_session(tmp_path, monkeypatch):
    from cryptography.fernet import Fernet
    from fastapi.testclient import TestClient
    monkeypatch.setenv('TOKEN_ENCRYPTION_KEY', Fernet.generate_key().decode())
    monkeypatch.setenv('DATABASE_PATH', str(tmp_path / 'api.sqlite'))
    monkeypatch.delenv('GOOGLE_APPLICATION_CREDENTIALS', raising=False)
    async def identity(token):
        return '7' if token == 'first-test-session' else '8'
    async def no_jobs(*args):
        return []
    monkeypatch.setattr(app, 'verify_session', identity)
    monkeypatch.setattr(app, 'all_jobs', no_jobs)
    with TestClient(app.app) as client:
        payload = {'session': 'first-test-session', 'push_token': 'test-device-push-token', 'city': 'Natal'}
        secret = client.post('/devices', json=payload).json()['secret']
        payload['session'] = 'another-test-session'
        response = client.post('/devices', json=payload, headers={'authorization': 'Bearer ' + secret})
        assert response.status_code == 403
