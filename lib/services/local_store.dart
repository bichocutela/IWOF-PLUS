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

  Future<void> setRegion(String city) async {
    await (await db).transaction((txn) async {
      final rows = await txn.query(
        'meta',
        where: 'key = ?',
        whereArgs: ['region'],
      );
      if (rows.isEmpty ||
          normalizeCity(rows.first['value'] as String) != normalizeCity(city)) {
        final versionRows = await txn.query(
          'meta',
          where: 'key = ?',
          whereArgs: ['region_version'],
        );
        final version = versionRows.isEmpty
            ? 0
            : int.parse(versionRows.first['value'] as String);
        await txn.insert('meta', {
          'key': 'region_version',
          'value': '${version + 1}',
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        await txn.delete(
          'baselines',
          where: 'city = ?',
          whereArgs: [normalizeCity(city)],
        );
      }
      await txn.insert('meta', {
        'key': 'region',
        'value': city,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
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
      final region = await txn.query(
        'meta',
        where: 'key = ?',
        whereArgs: ['region'],
      );
      if (region.isEmpty ||
          normalizeCity(region.first['value'] as String) !=
              normalizeCity(city)) {
        return <int>[];
      }
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
  Future<int?> recordPush(
    String city,
    Job job, {
    required bool delivered,
  }) async {
    if (normalizeCity(await region() ?? '') != normalizeCity(city)) return null;
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
