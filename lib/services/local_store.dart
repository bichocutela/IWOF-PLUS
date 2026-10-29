import 'dart:convert';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import '../core/models.dart';

class LocalStore {
  Database? _db;
  Future<Database> get db async => _db ??= await openDatabase(
    p.join(await getDatabasesPath(), 'iwof_plus.sqlite'),
    version: 1,
    onCreate: (db, _) async {
      await db.execute(
        'CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
      );
      await db.execute(
        'CREATE TABLE seen (city TEXT, job_id TEXT, PRIMARY KEY(city, job_id))',
      );
      await db.execute('CREATE TABLE baselines (city TEXT PRIMARY KEY)');
      await db.execute(
        'CREATE TABLE alerts (id INTEGER PRIMARY KEY AUTOINCREMENT, city TEXT, job_id TEXT, body TEXT, created TEXT, read INTEGER DEFAULT 0, delivered INTEGER DEFAULT 0, UNIQUE(city, job_id))',
      );
      await db.execute(
        'CREATE TABLE saved (job_id TEXT PRIMARY KEY, body TEXT)',
      );
    },
  );
  Future<String?> region() async {
    final rows = await (await db).query(
      'meta',
      where: 'key = ?',
      whereArgs: ['region'],
    );
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  Future<List<String>> regions() async {
    final rows = await (await db).query('meta', where: 'key = ?', whereArgs: ['regions']);
    if (rows.isNotEmpty) {
      final list = jsonDecode(rows.first['value'] as String) as List<dynamic>;
      return list.cast<String>();
    }
    final city = await region();
    return city == null || city.isEmpty ? [] : [city];
  }

  Future<void> setRegion(String city) => setRegions([city]);

  Future<void> setRegions(List<String> cities) async {
    final unique = <String, String>{};
    for (final city in cities) {
      final value = city.trim();
      if (value.isNotEmpty) unique[normalizeCity(value)] = value;
    }
    if (unique.isEmpty) throw ArgumentError('Selecione ao menos uma cidade.');
    await (await db).transaction((txn) async {
      final rows = await txn.query('meta', where: 'key IN (?, ?)', whereArgs: ['region', 'regions']);
      final values = {for (final row in rows) row['key'] as String: row['value'] as String};
      final old = values['regions'] != null
          ? (jsonDecode(values['regions']!) as List<dynamic>).cast<String>()
          : (values['region'] == null ? <String>[] : [values['region']!]);
      final oldKeys = old.map(normalizeCity).toSet();
      if (oldKeys.length != unique.length || !oldKeys.containsAll(unique.keys)) {
        final versionRows = await txn.query('meta', where: 'key = ?', whereArgs: ['region_version']);
        final version = versionRows.isEmpty ? 0 : int.parse(versionRows.first['value'] as String);
        await txn.insert('meta', {'key': 'region_version', 'value': '${version + 1}'}, conflictAlgorithm: ConflictAlgorithm.replace);
        for (final key in unique.keys.where((key) => !oldKeys.contains(key))) {
          await txn.delete('baselines', where: 'city = ?', whereArgs: [key]);
        }
      }
      await txn.insert('meta', {'key': 'region', 'value': unique.values.first}, conflictAlgorithm: ConflictAlgorithm.replace);
      await txn.insert('meta', {'key': 'regions', 'value': jsonEncode(unique.values.toList())}, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  Future<int> regionVersion() async {
    final rows = await (await db).query(
      'meta',
      where: 'key = ?',
      whereArgs: ['region_version'],
    );
    return rows.isEmpty ? 0 : int.parse(rows.first['value'] as String);
  }

  Future<List<int>> recordSnapshot(
    String city,
    List<Job> jobs, {
    int? revision,
  }) async {
    return (await db).transaction((txn) async {
      final rows = await txn.query('meta', where: 'key IN (?, ?)', whereArgs: ['region', 'regions']);
      final values = {for (final row in rows) row['key'] as String: row['value'] as String};
      final selected = values['regions'] != null
          ? (jsonDecode(values['regions']!) as List<dynamic>).cast<String>()
          : (values['region'] == null ? <String>[] : [values['region']!]);
      if (!selected.any((value) => normalizeCity(value) == normalizeCity(city))) return <int>[];
      final versions = await txn.query(
        'meta',
        where: 'key = ?',
        whereArgs: ['region_version'],
      );
      final currentVersion = versions.isEmpty
          ? 0
          : int.parse(versions.first['value'] as String);
      if (revision != null && revision != currentVersion) return <int>[];
      final key = normalizeCity(city);
      final baseline = await txn.query(
        'baselines',
        where: 'city = ?',
        whereArgs: [key],
      );
      final ids = <int>[];
      for (final job in jobs) {
        final known = await txn.query(
          'seen',
          where: 'city = ? AND job_id = ?',
          whereArgs: [key, job.id],
        );
        if (known.isNotEmpty) continue;
        await txn.insert('seen', {
          'city': key,
          'job_id': job.id,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
        if (baseline.isEmpty) continue;
        final inserted = await txn.insert('alerts', {
          'city': key,
          'job_id': job.id,
          'body': jsonEncode({...job.toJson(), 'region_label': city}),
          'created': DateTime.now().toIso8601String(),
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
        if (inserted > 0) ids.add(inserted);
      }
      await txn.insert('baselines', {
        'city': key,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      return ids;
    });
  }

  Future<List<Map<String, Object?>>> alerts({bool pending = false}) async =>
      (await db).query(
        'alerts',
        where: pending ? 'delivered = 0' : null,
        orderBy: 'id DESC',
        limit: pending ? null : 200,
      );
  Future<void> delivered(int id) async => (await db).update(
    'alerts',
    {'delivered': 1},
    where: 'id = ?',
    whereArgs: [id],
  );
  Future<void> markRead(int id) async => (await db).update(
    'alerts',
    {'read': 1},
    where: 'id = ?',
    whereArgs: [id],
  );
  Future<void> markAllAlertsRead() async {
    await (await db).update('alerts', {'read': 1}, where: 'read = 0');
  }

  Future<void> deleteAllAlerts() async {
    await (await db).delete('alerts');
  }

  Future<int?> recordPush(
    String city,
    Job job, {
    required bool delivered,
  }) async {
    if (!(await regions()).any((value) => normalizeCity(value) == normalizeCity(city))) return null;
    await (await db).insert('alerts', {
      'city': normalizeCity(city),
      'job_id': job.id,
      'body': jsonEncode({...job.toJson(), 'region_label': city}),
      'created': DateTime.now().toIso8601String(),
      'delivered': delivered ? 1 : 0,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    final rows = await (await db).query(
      'alerts',
      where: 'city = ? AND job_id = ?',
      whereArgs: [normalizeCity(city), job.id],
    );
    return rows.isEmpty ? null : rows.first['id'] as int;
  }

  Future<List<Job>> saved() async => (await (await db).query(
    'saved',
  )).map((e) => Job.fromJson(jsonDecode(e['body'] as String))).toList();
  Future<void> toggleSaved(Job job) async {
    final rows = await (await db).query(
      'saved',
      where: 'job_id = ?',
      whereArgs: [job.id],
    );
    if (rows.isEmpty) {
      await (await db).insert('saved', {
        'job_id': job.id,
        'body': jsonEncode(job.toJson()),
      });
    } else {
      await (await db).delete(
        'saved',
        where: 'job_id = ?',
        whereArgs: [job.id],
      );
    }
  }

  Future<void> clearAccount() async => (await db).transaction((txn) async {
    for (final table in ['meta', 'seen', 'baselines', 'alerts', 'saved']) {
      await txn.delete(table);
    }
  });
}

