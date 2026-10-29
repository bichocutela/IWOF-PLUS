import 'dart:ui';
import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import '../core/models.dart';
import 'iwof_api.dart';
import 'local_store.dart';
import 'location_service.dart';
import 'notifications.dart';
import 'remote_push.dart';

const secureStorage = FlutterSecureStorage(
  aOptions: AndroidOptions(encryptedSharedPreferences: true),
);
const monitorTask = 'iwof-region-monitor';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, _) async {
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();
    final prefs = await SharedPreferences.getInstance();
    final token = await secureStorage.read(key: 'session');
    if (token == null || prefs.getBool('alertsEnabled') != true) return true;
    final store = LocalStore();
    try {
      var region = await store.region();
      if (prefs.getBool('automaticRegion') != false &&
          prefs.getBool('backgroundLocation') == true &&
          await Geolocator.checkPermission() == LocationPermission.always &&
          await Geolocator.isLocationServiceEnabled()) {
        try {
          final gps = LocationService();
          final position = await gps.current();
          final next = await gps.city(position);
          final guard = RegionGuard()
            ..candidate = prefs.getString('regionCandidate')
            ..candidateSince = DateTime.tryParse(
              prefs.getString('regionCandidateSince') ?? '',
            );
          final accepted = guard.accept(
            region ?? '',
            next,
            position.accuracy,
            DateTime.now(),
          );
          if (guard.candidate == null) {
            await prefs.remove('regionCandidate');
            await prefs.remove('regionCandidateSince');
          } else {
            await prefs.setString('regionCandidate', guard.candidate!);
            await prefs.setString(
              'regionCandidateSince',
              guard.candidateSince!.toIso8601String(),
            );
          }
          if (accepted != null) {
            await store.setRegion(accepted);
            region = accepted;
          }
        } catch (_) {
          /* Keep the last region if GPS/geocoding is temporarily unavailable. */
        }
      }
      if (region == null || region.isEmpty) return true;
      // Remote push and local polling are mutually exclusive to avoid duplicate alerts.
      // Remote setup failure leaves local polling enabled.
      await RemotePush().sync();
      await prefs.reload();
      if (prefs.getBool('remoteActive') == true) return true;
      final revision = await store.regionVersion();
      final selected = await store.regions();
      final snapshots = <String, List<Job>>{};
      for (final city in selected) {
        snapshots[city] = await IwofApi().allJobs(token, city);
      }
      // Do not commit a snapshot from a previous account/disabled monitor.
      await prefs.reload();
      if (token != await secureStorage.read(key: 'session') ||
          prefs.getBool('alertsEnabled') != true) {
        return true;
      }
      for (final entry in snapshots.entries) {
        await store.recordSnapshot(entry.key, entry.value, revision: revision);
      }
      final notifications = JobNotifications();
      await notifications.initialize();
      await notifications.flush(store);
      await prefs.setString('lastCheck', DateTime.now().toIso8601String());
      await prefs.remove('monitorError');
      return true;
    } on SessionExpired {
      await prefs.setString(
        'monitorError',
        'Sua sessão expirou. Entre novamente.',
      );
      return true;
    } catch (_) {
      await prefs.setString(
        'monitorError',
        'Não foi possível verificar novas vagas. Uma nova tentativa será feita.',
      );
      return false;
    }
  });
}

Future<void> enableBackground() async {
  await Workmanager().registerPeriodicTask(
    monitorTask,
    monitorTask,
    frequency: const Duration(minutes: 15),
    constraints: Constraints(networkType: NetworkType.connected),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
  );
}

