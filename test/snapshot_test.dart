import 'package:flutter_test/flutter_test.dart';
import 'package:iwof_plus/core/models.dart';
import 'package:iwof_plus/services/local_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Job job(String id) => Job(
  id: id,
  title: 'Repositor',
  store: 'Loja',
  address: 'Centro',
  start: null,
  finish: null,
);
void main() {
  late LocalStore store;
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() async {
    store = LocalStore();
    await store.clearAccount();
    await store.setRegion('Natal');
  });
  tearDown(() async {
    await (await store.db).close();
  });
  test('bulk read and delete keep the seen snapshot and region', () async {
    await store.recordSnapshot('Natal', [job('1')]);
    await store.recordSnapshot('Natal', [job('1'), job('2'), job('3')]);
    expect(await store.alerts(), hasLength(2));
    await store.markAllAlertsRead();
    expect((await store.alerts()).every((a) => a['read'] == 1), isTrue);
    await store.deleteAllAlerts();
    expect(await store.alerts(), isEmpty);
    expect(await store.region(), 'Natal');
    expect(await store.recordSnapshot('Natal', [job('1'), job('2'), job('3')]), isEmpty);
  });

  test(
    'first snapshot is silent, repeated new IDs create a single alert',
    () async {
      expect(await store.recordSnapshot('Natal', [job('1')]), isEmpty);
      expect(
        await store.recordSnapshot('Natal', [job('1'), job('2')]),
        hasLength(1),
      );
      expect(await store.recordSnapshot('Natal', [job('2')]), isEmpty);
      await store.recordPush('nAtAl', job('2'), delivered: false);
      expect(await store.alerts(), hasLength(1));
    },
  );
  test('stale region is discarded and new region starts silently', () async {
    await store.recordSnapshot('Natal', [job('1')]);
    final oldVersion = await store.regionVersion();
    await store.setRegion('Parnamirim');
    expect(await store.recordSnapshot('Natal', [job('2')]), isEmpty);
    expect(await store.recordSnapshot('Parnamirim', [job('3')]), isEmpty);
    expect(
      await store.recordSnapshot('Parnamirim', [job('3'), job('4')]),
      hasLength(1),
    );
    await store.setRegion('Natal');
    expect(
      await store.recordSnapshot('Natal', [job('stale')], revision: oldVersion),
      isEmpty,
    );
    expect(await store.recordSnapshot('Natal', [job('1'), job('5')]), isEmpty);
  });
  test('multiple cities produce alerts only for selected cities and reject stale snapshots', () async {
    await store.setRegions(['Natal', 'Parnamirim']);
    final version = await store.regionVersion();
    expect(await store.regions(), ['Natal', 'Parnamirim']);
    await store.recordSnapshot('Natal', [job('n1')], revision: version);
    await store.recordSnapshot('Parnamirim', [job('p1')], revision: version);
    expect(await store.recordSnapshot('Natal', [job('n1'), job('n2')], revision: version), hasLength(1));
    expect(await store.recordSnapshot('Parnamirim', [job('p1'), job('p2')], revision: version), hasLength(1));
    await store.setRegions(['Natal']);
    expect(await store.recordSnapshot('Parnamirim', [job('p3')], revision: version), isEmpty);
    expect(await store.recordSnapshot('Natal', [job('n3')], revision: version), isEmpty);
    expect(await store.recordPush('Parnamirim', job('p4'), delivered: false), isNull);
  });

}

