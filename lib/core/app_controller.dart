import 'dart:async';
import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import '../services/background.dart';
import '../services/iwof_api.dart';
import '../services/local_store.dart';
import '../services/location_service.dart';
import '../services/notifications.dart';
import '../services/remote_push.dart';
import 'models.dart';

class AppController extends ChangeNotifier with WidgetsBindingObserver {
  final api = IwofApi();
  final store = LocalStore();
  final gps = LocationService();
  final notifications = JobNotifications();
  final push = RemotePush();
  final guard = RegionGuard();
  SharedPreferences? prefs;
  StreamSubscription<Position>? _location;
  Timer? _timer;
  String? token, region, error, pendingJobId;
  String search = '', selectedRole = '';
  List<Job> jobs = [], saved = [];
  List<String> cities = [];
  List<Map<String, Object?>> alerts = [];
  bool initialized = false, busy = false, loadingMore = false, automatic = true;
  bool alertsEnabled = false, backgroundLocation = false;
  int total = 0, page = 1;
  bool get remoteActive => prefs?.getBool('remoteActive') == true;
  bool get hasSession => token != null;
  List<Job> get visibleJobs => jobs
      .where(
        (job) =>
            (selectedRole.isEmpty || job.title == selectedRole) &&
            '${job.title} ${job.store}'.toLowerCase().contains(
              search.toLowerCase(),
            ),
      )
      .toList();
  List<String> get roles => jobs.map((j) => j.title).toSet().toList()..sort();
  int get unread => alerts.where((e) => e['read'] == 0).length;

  Future<void> initialize() async {
    WidgetsBinding.instance.addObserver(this);
    prefs = await SharedPreferences.getInstance();
    token = await secureStorage.read(key: 'session');
    region = await store.region();
    automatic = prefs!.getBool('automaticRegion') ?? true;
    alertsEnabled = prefs!.getBool('alertsEnabled') ?? false;
    backgroundLocation = prefs!.getBool('backgroundLocation') ?? false;
    await notifications.initialize(onTap: openJob);
    try {
      await push.initialize(
        onTap: openJob,
        onMessage: () {
          unawaited(loadLocal());
        },
      );
    } catch (_) {
      await prefs!.setBool('remoteActive', false);
    }
    final payload = await notifications.launchPayload();
    if (payload != null) openJob(payload);
    await loadLocal();
    initialized = true;
    notifyListeners();
    if (hasSession) {
      await loadCities();
      if (automatic) await locate(prompt: false);
      if (region != null) await refresh();
      await startLocationStream();
      if (alertsEnabled) await enableBackground();
    }
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (hasSession && automatic && (_foreground || backgroundLocation)) {
        unawaited(confirmLocation());
      }
      if (hasSession && alertsEnabled && !busy && _foreground) {
        unawaited(checkNew());
      }
    });
  }

  void openJob(String id) {
    pendingJobId = id;
    notifyListeners();
  }

  void consumeJob() {
    pendingJobId = null;
  }

  Future<void> login(String phone, String password) async {
    if (busy) return;
    busy = true;
    error = null;
    notifyListeners();
    try {
      token = await api.login(phone, password);
      await secureStorage.write(key: 'session', value: token);
      await loadCities();
    } catch (e) {
      error = cleanError(e);
      rethrow;
    } finally {
      busy = false;
      notifyListeners();
    }
    if (automatic) await locate(prompt: true);
    if (region != null) await refresh();
    await startLocationStream();
  }

  Future<void> logout() async {
    // Require successful remote removal so logging out cannot leave an active server monitor.
    await push.unregister();
    token = null;
    await _location?.cancel();
    _location = null;
    await Workmanager().cancelByUniqueName(monitorTask);
    await secureStorage.delete(key: 'session');
    await store.clearAccount();
    await notifications.plugin.cancelAll();
    await prefs!.setBool('remoteActive', false);
    await prefs!.setBool('alertsEnabled', false);
    alertsEnabled = false;
    jobs = [];
    saved = [];
    alerts = [];
    region = null;
    total = 0;
    error = null;
    notifyListeners();
  }

  Future<void> loadCities() async {
    try {
      cities = await api.cities(token!);
    } catch (e) {
      error = cleanError(e);
    }
    notifyListeners();
  }

  Future<void> loadLocal() async {
    saved = await store.saved();
    alerts = await store.alerts();
    notifyListeners();
  }

  Future<void> chooseRegion(String city, {bool manual = true}) async {
    _regionRevision++;
    if (manual) {
      automatic = false;
      await prefs!.setBool('automaticRegion', false);
      await _location?.cancel();
      _location = null;
    }
    region = city.trim();
    selectedRole = '';
    jobs = [];
    total = 0;
    page = 1;
    await store.setRegion(region!);
    await push.sync();
    notifyListeners();
    await refresh();
    if (!prefs!.containsKey('alertsEnabled')) {
      await prefs!.setBool('alertsEnabled', false);
      try {
        await setAlerts(true);
      } catch (e) {
        error = cleanError(e);
        notifyListeners();
      }
    } else if (alertsEnabled) {
      await checkNew();
    }
  }

  Future<void> locate({required bool prompt}) async {
    final revision = _regionRevision;
    try {
      if (prompt) {
        if (!await gps.ensurePermission()) {
          throw Exception('Permita a localização ou escolha uma cidade.');
        }
      } else {
        final permission = await Geolocator.checkPermission();
        if (permission != LocationPermission.whileInUse &&
            permission != LocationPermission.always) {
          return;
        }
        if (!await Geolocator.isLocationServiceEnabled()) return;
      }
      final position = await gps.current();
      final city = await gps.city(position);
      if (revision != _regionRevision || !hasSession) return;
      if (!prompt &&
          region != null &&
          normalizeCity(region!) != normalizeCity(city)) {
        final accepted = guard.accept(
          region!,
          city,
          position.accuracy,
          DateTime.now(),
        );
        if (accepted == null) return;
      }
      automatic = true;
      await prefs!.setBool('automaticRegion', true);
      await chooseRegion(city, manual: false);
      await startLocationStream();
    } catch (e) {
      error = cleanError(e);
      notifyListeners();
    }
  }

  bool _resolvingLocation = false;
  int _regionRevision = 0;
  Future<void> startLocationStream() async {
    await _location?.cancel();
    _location = null;
    if (!automatic || !hasSession) return;
    final permission = await Geolocator.checkPermission();
    if (permission != LocationPermission.whileInUse &&
        permission != LocationPermission.always) {
      return;
    }
    _location = gps
        .stream(background: backgroundLocation)
        .listen(
          (position) {
            unawaited(observePosition(position));
          },
          onError: (_) {
            error =
                'Não foi possível acompanhar o GPS. A última região foi mantida.';
            notifyListeners();
          },
        );
  }

  Future<void> confirmLocation() async {
    if (!automatic || !hasSession || _resolvingLocation) return;
    try {
      await observePosition(await gps.current());
    } catch (_) {
      /* Keep region. */
    }
  }

  Future<void> observePosition(Position position) async {
    if (_resolvingLocation || !automatic || !hasSession) return;
    _resolvingLocation = true;
    final revision = _regionRevision;
    try {
      final next = await gps.city(position);
      if (!automatic || !hasSession || revision != _regionRevision) return;
      final accepted = guard.accept(
        region ?? '',
        next,
        position.accuracy,
        DateTime.now(),
      );
      if (accepted != null) await chooseRegion(accepted, manual: false);
    } catch (_) {
      /* Keep last known region. */
    } finally {
      _resolvingLocation = false;
    }
  }

  Future<void> setBackgroundLocation(bool enabled) async {
    if (enabled) {
      if (!await gps.ensurePermission()) {
        throw Exception('Permita a localização primeiro.');
      }
      if (await Geolocator.checkPermission() != LocationPermission.always) {
        await Geolocator.openAppSettings();
        throw Exception(
          'Nas permissões do Android, escolha localização “Permitir o tempo todo” e ative esta opção novamente.',
        );
      }
    }
    backgroundLocation = enabled;
    await prefs!.setBool('backgroundLocation', enabled);
    await startLocationStream();
    notifyListeners();
  }

  Future<void> setAlerts(bool enabled) async {
    if (enabled && region == null) {
      throw Exception('Escolha uma região antes de ativar os avisos.');
    }
    if (enabled && !await notifications.permission()) {
      throw Exception('Permita as notificações nas configurações do Android.');
    }
    alertsEnabled = enabled;
    await prefs!.setBool('alertsEnabled', enabled);
    if (enabled) {
      await checkNew();
      await enableBackground();
    } else {
      await Workmanager().cancelByUniqueName(monitorTask);
      await notifications.plugin.cancelAll();
    }
    await push.sync();
    notifyListeners();
  }

  Future<void> refresh() async {
    if (token == null || region == null || busy) return;
    final requestedRegion = region!;
    final requestedToken = token!;
    busy = true;
    error = null;
    notifyListeners();
    try {
      final result = await api.jobs(requestedToken, requestedRegion, 1);
      if (region != requestedRegion || token != requestedToken) return;
      jobs = result.jobs;
      total = result.total;
      page = 1;
    } catch (e) {
      error = cleanError(e);
    } finally {
      busy = false;
      notifyListeners();
      if (region != requestedRegion && token != null) unawaited(refresh());
    }
  }

  Future<void> loadMore() async {
    if (loadingMore ||
        busy ||
        jobs.length >= total ||
        token == null ||
        region == null) {
      return;
    }
    final city = region!, session = token!;
    loadingMore = true;
    notifyListeners();
    try {
      final result = await api.jobs(session, city, page + 1);
      if (city != region || token != session) return;
      final byId = {for (final job in jobs) job.id: job};
      for (final job in result.jobs) {
        byId[job.id] = job;
      }
      if (byId.length == jobs.length && jobs.length < result.total) {
        throw Exception(
          'Não foi possível avançar a paginação. Atualize a lista.',
        );
      }
      jobs = byId.values.toList();
      page++;
      total = result.total;
    } catch (e) {
      error = cleanError(e);
    } finally {
      loadingMore = false;
      notifyListeners();
    }
  }

  bool _checking = false;
  bool _foreground = true;
  Future<void> checkNew() async {
    if (_checking || !alertsEnabled || token == null || region == null) return;
    _checking = true;
    final city = region!, session = token!;
    try {
      await push.sync();
      if (!remoteActive) {
        final revision = await store.regionVersion();
        final result = await api.allJobs(session, city);
        if (!alertsEnabled || token != session || region != city) return;
        await store.recordSnapshot(city, result, revision: revision);
        await notifications.flush(store);
      }
      await prefs!.setString('lastCheck', DateTime.now().toIso8601String());
      await loadLocal();
    } catch (e) {
      error = cleanError(e);
      notifyListeners();
    } finally {
      _checking = false;
    }
  }

  Future<void> toggleSaved(Job job) async {
    await store.toggleSaved(job);
    await loadLocal();
  }

  Future<void> readAlert(Map<String, Object?> alert) async {
    await store.markRead(alert['id'] as int);
    await loadLocal();
    openJob('${alert['job_id']}');
  }

  String alertRegion(Map<String, Object?> alert) =>
      '${jsonDecode(alert['body'] as String)['region_label'] ?? alert['city']}';
  Job alertJob(Map<String, Object?> alert) =>
      Job.fromJson(jsonDecode(alert['body'] as String));
  static String cleanError(Object e) => e.toString().replaceFirst(
    RegExp(r'^(Exception|FormatException):\s*'),
    '',
  );
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (state == AppLifecycleState.resumed && hasSession) {
      unawaited(_resume());
    } else if (state == AppLifecycleState.paused && !backgroundLocation) {
      unawaited(_location?.cancel());
      _location = null;
    }
  }

  Future<void> _resume() async {
    await prefs!.reload();
    region = await store.region();
    await loadLocal();
    if (automatic) await locate(prompt: false);
    await startLocationStream();
    await checkNew();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    unawaited(_location?.cancel());
    super.dispose();
  }
}
