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
