"""Run as one persistent process behind HTTPS, with a persistent /data volume."""
import asyncio
import base64
import hashlib
import json
import logging
import os
import secrets
from contextlib import asynccontextmanager, suppress
from datetime import datetime, timezone, timedelta
from pathlib import Path

import httpx
from cryptography.fernet import Fernet
from fastapi import FastAPI, Header, HTTPException
from pydantic import BaseModel, Field, SecretStr

from monitor import Store, city_key
from settings import encryption_cipher, firebase_credentials

API_URL = 'https://59pcbz0e53.execute-api.us-east-1.amazonaws.com/production/graphql'
logger = logging.getLogger('iwof_plus')
store = None
cipher = None
lock = asyncio.Lock()
push_ready = False
wake = asyncio.Event()
FIELDS = 'id job { name } store { name address image company { image } } job_store { value percentage } start_at finish_at'


class UpstreamError(Exception):
    pass


class ExpiredSession(UpstreamError):
    pass


async def graphql(token, query):
    async with httpx.AsyncClient(timeout=35) as client:
        response = await client.post(API_URL, json={'query': query}, headers={
            'authorization': 'Bearer ' + token, 'x-iwof-platform': 'android',
            'x-iwof-app-version': '2.3.14'})
    if response.status_code in (401, 403):
        raise ExpiredSession()
    if response.status_code != 200:
        raise UpstreamError()
    body = response.json()
    if body.get('errors'):
        message = str(body['errors'][0].get('message', '')).lower()
        if any(value in message for value in ['token', 'jwt', 'unauth', 'expir']):
            raise ExpiredSession()
        raise UpstreamError()
    return body.get('data') or {}


async def verify_session(token):
    # The decoded ID is only a lookup hint, never an authorization decision.
    try:
        payload = token.split('.')[1]
        claimed_id = str(json.loads(base64.urlsafe_b64decode(payload + '=' * (-len(payload) % 4)))['id'])
        if not claimed_id.isdigit():
            raise ValueError()
        result = await graphql(token, '{ worker(id: ' + json.dumps(claimed_id) + ') { id } }')
        if str((result.get('worker') or {}).get('id')) != claimed_id:
            raise ValueError()
        return claimed_id
    except (ValueError, TypeError, KeyError, IndexError, ExpiredSession):
        raise HTTPException(401, 'Sessão inválida ou expirada') from None
    except (httpx.HTTPError, UpstreamError):
        raise HTTPException(503, 'Não foi possível validar a sessão') from None


async def all_jobs(token, city):
    jobs = {}
    for page in range(1, 251):
        query = '{ workerRequestsNewApp(page: %d, status: "NOVO", address: {city: %s}) { totalResults requests { %s } } }' % (page, json.dumps(city), FIELDS)
        data = (await graphql(token, query)).get('workerRequestsNewApp')
        if not isinstance(data, dict) or 'totalResults' not in data:
            raise UpstreamError()
        rows = data.get('requests') or []
        previous_count = len(jobs)
        for job in rows:
            jobs[str(job['id'])] = job
        if len(jobs) >= int(data['totalResults']):
            return list(jobs.values())
        if not rows or len(jobs) == previous_count:
            raise UpstreamError('Incomplete pagination')
        await asyncio.sleep(.2)
    raise UpstreamError('Safety limit reached')


def authenticate(authorization):
    if not authorization or not authorization.startswith('Bearer '):
        raise HTTPException(401, 'Autenticação necessária')
    digest = hashlib.sha256(authorization[7:].encode()).hexdigest()
    with store.connection() as db:
        row = db.execute('SELECT * FROM devices WHERE secret_hash=?', (digest,)).fetchone()
    if not row:
        raise HTTPException(401, 'Dispositivo não registrado')
    return dict(row)


class DeviceInput(BaseModel):
    session: SecretStr = Field(min_length=10, max_length=8192)
    push_token: SecretStr = Field(min_length=10, max_length=4096)
    city: str = Field(min_length=1, max_length=120)
    enabled: bool = True


@asynccontextmanager
async def lifespan(app):
    global store, cipher, push_ready, lock, wake
    lock = asyncio.Lock()
    wake = asyncio.Event()
    push_ready = False
    cipher = encryption_cipher(os.environ.get('TOKEN_ENCRYPTION_KEY'))
    path = Path(os.environ.get('DATABASE_PATH', '/data/iwof.sqlite'))
    path.parent.mkdir(parents=True, exist_ok=True)
    store = Store(path)
    credential = firebase_credentials()
    if credential is not None:
        import firebase_admin
        firebase_admin.initialize_app(credential)
        push_ready = True
    task = asyncio.create_task(scheduler())
    yield
    task.cancel()
    with suppress(asyncio.CancelledError):
        await task


app = FastAPI(title='IWOF PLUS Monitor', lifespan=lifespan, docs_url=None, redoc_url=None)


@app.get('/health')
async def health():
    return {'ok': True, 'push_ready': push_ready}


@app.post('/devices')
async def register(data: DeviceInput, authorization: str | None = Header(default=None)):
    owner = await verify_session(data.session.get_secret_value())
    secret = None
    async with lock:
        existing = authenticate(authorization) if authorization else None
        if existing and existing['owner'] != owner:
            raise HTTPException(403, 'Dispositivo pertence a outra sessão')
        device_id = existing['id'] if existing else secrets.token_hex(16)
        if not existing:
            secret = secrets.token_urlsafe(32)
        secret_hash = existing['secret_hash'] if existing else hashlib.sha256(secret.encode()).hexdigest()
        revision = existing['revision'] if existing else 0
        if existing and (city_key(existing['city']) != city_key(data.city) or bool(existing['enabled']) != data.enabled):
            revision += 1
        with store.connection() as db:
            duplicate = db.execute('SELECT id FROM devices WHERE push_token=?', (data.push_token.get_secret_value(),)).fetchone()
            if duplicate and duplicate['id'] != device_id:
                raise HTTPException(409, 'Dispositivo já registrado; encerre a sessão anterior')
            db.execute('''INSERT INTO devices(id,secret_hash,owner,session,push_token,city,enabled,revision)
                VALUES (?,?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET session=excluded.session,
                push_token=excluded.push_token,city=excluded.city,enabled=excluded.enabled,revision=excluded.revision,error=NULL''',
                (device_id, secret_hash, owner, cipher.encrypt(data.session.get_secret_value().encode()).decode(),
                 data.push_token.get_secret_value(), data.city.strip(), int(data.enabled), revision))
            db.execute('UPDATE outbox SET sent=1 WHERE device=? AND revision<>?', (device_id, revision))
    if data.enabled and (not existing or existing['revision'] != revision):
        wake.set()
    return {'secret': secret, 'push_ready': push_ready}


@app.delete('/devices/me')
async def remove(authorization: str | None = Header(default=None)):
    async with lock:
        device = authenticate(authorization)
        store.delete_device(device['id'])
    return {'ok': True}


@app.get('/devices/me')
async def status(authorization: str | None = Header(default=None)):
    device = authenticate(authorization)
    return {key: device[key] for key in ['city', 'enabled', 'last_check', 'error']}


def send_push(row, device):
    from firebase_admin import messaging
    job = json.loads(row['body'])
    messaging.send(messaging.Message(token=device['push_token'],
        data={'job_id': row['job'], 'city': row['city'], 'job': row['body']},
        android=messaging.AndroidConfig(priority='high', ttl=timedelta(seconds=900))))


async def monitor_once():
    with store.connection() as db:
        devices = [dict(row) for row in db.execute('SELECT * FROM devices WHERE enabled=1')]
    for device in devices:
        with store.connection() as db:
            baseline = db.execute('SELECT revision FROM baselines WHERE device=? AND city=?',
                (device['id'], city_key(device['city']))).fetchone()
        if baseline and baseline['revision'] == device['revision'] and device['last_check']:
            last = datetime.fromisoformat(device['last_check'])
            if (datetime.now(timezone.utc) - last).total_seconds() < max(900, int(os.environ.get('POLL_SECONDS', '900'))):
                continue
        try:
            token = cipher.decrypt(device['session'].encode()).decode()
            jobs = await all_jobs(token, device['city'])
            async with lock:
                store.snapshot(device['id'], device['city'], device['revision'], jobs)
                with store.connection() as db:
                    db.execute('UPDATE devices SET last_check=?,error=NULL WHERE id=? AND revision=?',
                        (datetime.now(timezone.utc).isoformat(), device['id'], device['revision']))
        except ExpiredSession:
            with store.connection() as db:
                db.execute('UPDATE devices SET enabled=0,error=? WHERE id=? AND session=?',
                           ('Sessão expirada. Entre novamente no app.', device['id'], device['session']))
        except Exception:
            # Never log tokens, upstream bodies, names, GPS coordinates or HTTP request headers.
            logger.warning('Falha temporária no monitoramento; nova tentativa no próximo ciclo.')
            with store.connection() as db:
                db.execute('UPDATE devices SET error=? WHERE id=?', ('Consulta temporariamente indisponível', device['id']))
    if not push_ready:
        return
    async with lock:
        with store.connection() as db:
            pending = [dict(row) for row in db.execute('SELECT * FROM outbox WHERE sent=0 AND attempts<10 ORDER BY id LIMIT 100')]
        for row in pending:
            with store.connection() as db:
                device = db.execute('SELECT * FROM devices WHERE id=?', (row['device'],)).fetchone()
            if not device or not device['enabled'] or device['revision'] != row['revision']:
                with store.connection() as db:
                    db.execute('UPDATE outbox SET sent=1 WHERE id=?', (row['id'],))
                continue
            try:
                await asyncio.to_thread(send_push, row, dict(device))
                with store.connection() as db:
                    db.execute('UPDATE outbox SET sent=1 WHERE id=?', (row['id'],))
            except Exception:
                with store.connection() as db:
                    db.execute('UPDATE outbox SET attempts=attempts+1 WHERE id=?', (row['id'],))
                logger.warning('Falha de entrega push; mensagem mantida para nova tentativa.')


async def scheduler():
    interval = max(900, int(os.environ.get('POLL_SECONDS', '900')))
    while True:
        wake.clear()
        try:
            await monitor_once()
        except Exception:
            logger.warning('Ciclo interrompido; nova tentativa agendada.')
        try:
            await asyncio.wait_for(wake.wait(), timeout=interval)
        except asyncio.TimeoutError:
            pass
