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
                  kind TEXT NOT NULL DEFAULT 'new',
                  sent INTEGER DEFAULT 0, attempts INTEGER DEFAULT 0);
                CREATE TABLE IF NOT EXISTS active (
                  device TEXT, city TEXT, job TEXT,
                  PRIMARY KEY(device, city, job));
                CREATE TABLE IF NOT EXISTS active_baselines (
                  device TEXT, city TEXT, revision INTEGER,
                  PRIMARY KEY(device, city));
            ''')
            # Old installations must keep their pending outbox while removing
            # the per-job UNIQUE constraint: one job can be available again.
            columns = {row['name'] for row in db.execute('PRAGMA table_info(outbox)')}
            if 'kind' not in columns:
                db.executescript('''
                    ALTER TABLE outbox RENAME TO outbox_legacy;
                    CREATE TABLE outbox (
                      id INTEGER PRIMARY KEY AUTOINCREMENT, device TEXT,
                      city TEXT, job TEXT, body TEXT, revision INTEGER,
                      kind TEXT NOT NULL DEFAULT 'new',
                      sent INTEGER DEFAULT 0, attempts INTEGER DEFAULT 0);
                    INSERT INTO outbox(id, device, city, job, body, revision,
                                       kind, sent, attempts)
                      SELECT id, device, city, job, body, revision,
                             'new', sent, attempts FROM outbox_legacy;
                    DROP TABLE outbox_legacy;
                ''')

    @contextmanager
    def connection(self):
        with sqlite3.connect(self.path, timeout=30) as db:
            db.row_factory = sqlite3.Row
            yield db

    def snapshot(self, device_id, city, revision, jobs):
        """Alert on first appearance and later returns, not on repeated scans.

        A fresh region/revision builds a silent baseline. The first scan after
        upgrading an older database also builds its active-job baseline safely.
        """
        key = city_key(city)
        with self.connection() as db:
            db.execute('BEGIN IMMEDIATE')
            current = db.execute('SELECT * FROM devices WHERE id=?', (device_id,)).fetchone()
            if not current or not current['enabled'] or current['revision'] != revision or city_key(current['city']) != key:
                return []
            baseline = db.execute('SELECT revision FROM baselines WHERE device=? AND city=?',
                                  (device_id, key)).fetchone()
            initialized = baseline is not None and baseline['revision'] == revision
            active_baseline = db.execute(
                'SELECT revision FROM active_baselines WHERE device=? AND city=?',
                (device_id, key)).fetchone()
            active_initialized = active_baseline is not None and active_baseline['revision'] == revision
            previous_active = {
                row['job'] for row in db.execute(
                    'SELECT job FROM active WHERE device=? AND city=?', (device_id, key))}
            known = {
                row['job'] for row in db.execute(
                    'SELECT job FROM seen WHERE device=? AND city=?', (device_id, key))}
            available = {str(job['id']): job for job in jobs}
            created = []
            for job_id, job in available.items():
                first_seen = job_id not in known
                if first_seen:
                    db.execute('INSERT OR IGNORE INTO seen VALUES (?,?,?)', (device_id, key, job_id))
                    known.add(job_id)
                returned = active_initialized and not first_seen and job_id not in previous_active
                if initialized and (first_seen or returned):
                    kind = 'returned' if returned else 'new'
                    cursor = db.execute(
                        'INSERT INTO outbox(device,city,job,body,revision,kind) VALUES (?,?,?,?,?,?)',
                        (device_id, city, job_id, json.dumps(job), revision, kind))
                    created.append(cursor.lastrowid)
            for job_id in previous_active - available.keys():
                db.execute('DELETE FROM active WHERE device=? AND city=? AND job=?',
                           (device_id, key, job_id))
            for job_id in available.keys() - previous_active:
                db.execute('INSERT OR IGNORE INTO active VALUES (?,?,?)', (device_id, key, job_id))
            db.execute('INSERT OR REPLACE INTO baselines VALUES (?,?,?)', (device_id, key, revision))
            db.execute('INSERT OR REPLACE INTO active_baselines VALUES (?,?,?)', (device_id, key, revision))
            return created

    def delete_device(self, device_id):
        with self.connection() as db:
            db.execute('BEGIN IMMEDIATE')
            for table in ['outbox', 'seen', 'baselines', 'active', 'active_baselines']:
                db.execute(f'DELETE FROM {table} WHERE device=?', (device_id,))
            db.execute('DELETE FROM devices WHERE id=?', (device_id,))
