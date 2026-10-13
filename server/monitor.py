"""SQLite snapshot/outbox. No credentials are stored in this module."""
import json
import sqlite3
import unicodedata
from contextlib import contextmanager


def city_key(value):
    return ' '.join(''.join(c for c in unicodedata.normalize('NFD', value.lower())
                           if not unicodedata.combining(c)).split())


class Store:
    def __init__(self, path):
        self.path = str(path)
        with self.connection() as db:
            db.executescript('''
                PRAGMA journal_mode=WAL;
                CREATE TABLE IF NOT EXISTS devices (
                  id TEXT PRIMARY KEY, secret_hash TEXT UNIQUE, owner TEXT,
                  session TEXT, push_token TEXT UNIQUE, city TEXT,
                  enabled INTEGER, revision INTEGER DEFAULT 0,
                  last_check TEXT, error TEXT);
                CREATE TABLE IF NOT EXISTS baselines (
                  device TEXT, city TEXT, revision INTEGER,
                  PRIMARY KEY(device, city));
                CREATE TABLE IF NOT EXISTS seen (
                  device TEXT, city TEXT, job TEXT,
                  PRIMARY KEY(device, city, job));
                CREATE TABLE IF NOT EXISTS outbox (
                  id INTEGER PRIMARY KEY AUTOINCREMENT, device TEXT,
                  city TEXT, job TEXT, body TEXT, revision INTEGER,
                  sent INTEGER DEFAULT 0, attempts INTEGER DEFAULT 0,
                  UNIQUE(device, city, job));
            ''')

    @contextmanager
    def connection(self):
        with sqlite3.connect(self.path, timeout=30) as db:
            db.row_factory = sqlite3.Row
            yield db

    def snapshot(self, device_id, city, revision, jobs):
        """Commit only complete results belonging to the current region/version."""
        key = city_key(city)
        with self.connection() as db:
            db.execute('BEGIN IMMEDIATE')
            current = db.execute('SELECT * FROM devices WHERE id=?', (device_id,)).fetchone()
            if not current or not current['enabled'] or current['revision'] != revision or city_key(current['city']) != key:
                return []
            baseline = db.execute('SELECT revision FROM baselines WHERE device=? AND city=?', (device_id, key)).fetchone()
            initialized = baseline is not None and baseline['revision'] == revision
            created = []
            for job in jobs:
                job_id = str(job['id'])
                known = db.execute('SELECT 1 FROM seen WHERE device=? AND city=? AND job=?', (device_id, key, job_id)).fetchone()
                if known:
                    continue
                db.execute('INSERT OR IGNORE INTO seen VALUES (?,?,?)', (device_id, key, job_id))
                if initialized:
                    cursor = db.execute('INSERT OR IGNORE INTO outbox(device,city,job,body,revision) VALUES (?,?,?,?,?)',
                                        (device_id, city, job_id, json.dumps(job), revision))
                    if cursor.rowcount:
                        created.append(cursor.lastrowid)
            db.execute('INSERT OR REPLACE INTO baselines VALUES (?,?,?)', (device_id, key, revision))
            return created

    def delete_device(self, device_id):
        with self.connection() as db:
            db.execute('BEGIN IMMEDIATE')
            for table in ['outbox', 'seen', 'baselines']:
                db.execute(f'DELETE FROM {table} WHERE device=?', (device_id,))
            db.execute('DELETE FROM devices WHERE id=?', (device_id,))
