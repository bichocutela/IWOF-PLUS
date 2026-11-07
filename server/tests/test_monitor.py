from monitor import Store


def setup(tmp_path):
    store = Store(tmp_path / 'test.sqlite')
    with store.connection() as db:
        db.execute('INSERT INTO devices(id,city,enabled,revision) VALUES (?,?,?,?)', ('a', 'Natal', 1, 0))
    return store


def test_first_snapshot_silent_and_new_ids_once(tmp_path):
    store = setup(tmp_path)
    assert store.snapshot('a', 'Natal', 0, [{'id': '1'}]) == []
    assert len(store.snapshot('a', 'Natal', 0, [{'id': '1'}, {'id': '2'}])) == 1
    assert store.snapshot('a', 'Natal', 0, [{'id': '2'}]) == []
    assert store.snapshot('a', 'Natal', 0, [{'id': '1'}, {'id': '2'}]) == []


def test_previous_region_response_is_discarded(tmp_path):
    store = setup(tmp_path)
    store.snapshot('a', 'Natal', 0, [{'id': '1'}])
    with store.connection() as db:
        db.execute('UPDATE devices SET city=?, revision=1 WHERE id=?', ('Parnamirim', 'a'))
    assert store.snapshot('a', 'Natal', 0, [{'id': '2'}]) == []
    assert store.snapshot('a', 'Parnamirim', 1, [{'id': '3'}]) == []
    assert len(store.snapshot('a', 'Parnamirim', 1, [{'id': '3'}, {'id': '4'}])) == 1


def test_returning_region_starts_with_silent_baseline(tmp_path):
    store = setup(tmp_path)
    store.snapshot('a', 'Natal', 0, [{'id': '1'}])
    with store.connection() as db:
        db.execute('UPDATE devices SET revision=2 WHERE id=?', ('a',))
    assert store.snapshot('a', 'Natal', 2, [{'id': '1'}, {'id': '5'}]) == []
    assert len(store.snapshot('a', 'Natal', 2, [{'id': '6'}])) == 1


def test_disabled_and_deleted_device_do_not_create_alerts(tmp_path):
    store = setup(tmp_path)
    store.snapshot('a', 'Natal', 0, [{'id': '1'}])
    with store.connection() as db:
        db.execute('UPDATE devices SET enabled=0 WHERE id=?', ('a',))
    assert store.snapshot('a', 'Natal', 0, [{'id': '2'}]) == []
    store.delete_device('a')
    assert store.snapshot('a', 'Natal', 0, [{'id': '2'}]) == []



def test_returned_job_notifies_again_only_after_disappearing(tmp_path):
    store = setup(tmp_path)
    assert store.snapshot('a', 'Natal', 0, [{'id': '1'}]) == []
    assert store.snapshot('a', 'Natal', 0, [{'id': '1'}]) == []
    assert store.snapshot('a', 'Natal', 0, []) == []
    first_return = store.snapshot('a', 'Natal', 0, [{'id': '1'}])
    assert len(first_return) == 1
    assert store.snapshot('a', 'Natal', 0, [{'id': '1'}]) == []
    assert store.snapshot('a', 'Natal', 0, []) == []
    second_return = store.snapshot('a', 'Natal', 0, [{'id': '1'}])
    assert len(second_return) == 1
    assert first_return != second_return
    with store.connection() as db:
        rows = db.execute('SELECT kind FROM outbox ORDER BY id').fetchall()
    assert [row['kind'] for row in rows] == ['returned', 'returned']


def test_new_job_and_reopen_have_distinct_outbox_events(tmp_path):
    store = setup(tmp_path)
    store.snapshot('a', 'Natal', 0, [{'id': '1'}])
    assert len(store.snapshot('a', 'Natal', 0, [{'id': '1'}, {'id': '2'}])) == 1
    store.snapshot('a', 'Natal', 0, [{'id': '1'}])
    assert len(store.snapshot('a', 'Natal', 0, [{'id': '1'}, {'id': '2'}])) == 1
    with store.connection() as db:
        rows = db.execute('SELECT job, kind FROM outbox ORDER BY id').fetchall()
    assert [(row['job'], row['kind']) for row in rows] == [('2', 'new'), ('2', 'returned')]


def test_legacy_outbox_keeps_pending_messages_and_can_repeat_job(tmp_path):
    import sqlite3
    path = tmp_path / 'legacy.sqlite'
    with sqlite3.connect(path) as db:
        db.execute('''CREATE TABLE outbox (
            id INTEGER PRIMARY KEY AUTOINCREMENT, device TEXT,
            city TEXT, job TEXT, body TEXT, revision INTEGER,
            sent INTEGER DEFAULT 0, attempts INTEGER DEFAULT 0,
            UNIQUE(device, city, job))''')
        db.execute('''INSERT INTO outbox(device,city,job,body,revision)
                      VALUES ('a','Natal','1','{"id":"1"}',0)''')
    store = Store(path)
    with store.connection() as db:
        rows = db.execute('SELECT job, kind, sent FROM outbox').fetchall()
        assert [(row['job'], row['kind'], row['sent']) for row in rows] == [('1', 'new', 0)]
        db.execute('''INSERT INTO outbox(device,city,job,body,revision,kind)
                      VALUES ('a','Natal','1','{"id":"1"}',0,'returned')''')
        assert db.execute('SELECT COUNT(*) FROM outbox').fetchone()[0] == 2
