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
