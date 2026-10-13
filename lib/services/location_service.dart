import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import '../core/models.dart';

class RegionGuard {
  String? candidate;
  DateTime? candidateSince;
  String? accept(String current, String next, double accuracy, DateTime now) {
    if (accuracy > 500 || next.isEmpty) return null;
    if (current.isEmpty) return next;
    if (normalizeCity(current) == normalizeCity(next)) {
      candidate = null;
      candidateSince = null;
      return null;
    }
    if (candidate == null || normalizeCity(candidate!) != normalizeCity(next)) {
      candidate = next;
      candidateSince = now;
      return null;
    }
    if (now.difference(candidateSince!) < const Duration(minutes: 2)) {
      return null;
    }
    candidate = null;
    candidateSince = null;
    return next;
  }
}

class LocationService {
  Future<bool> ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw Exception('Ative o GPS para identificar sua região.');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always;
  }

  Future<String> city(Position position) async {
    if (position.accuracy > 500) {
      throw Exception(
        'A localização está imprecisa. Tente novamente em instantes.',
      );
    }
    final places = await placemarkFromCoordinates(
      position.latitude,
      position.longitude,
    ).timeout(const Duration(seconds: 20));
    if (places.isEmpty) {
      throw Exception('Não foi possível identificar a cidade.');
    }
    // Brazilian Android geocoders often expose the municipality in subAdministrativeArea.
    final place = places.first;
    final municipality =
        (place.subAdministrativeArea?.trim().isNotEmpty ?? false)
        ? place.subAdministrativeArea!.trim()
        : place.locality?.trim() ?? '';
    if (municipality.isEmpty) {
      throw Exception('Escolha sua cidade manualmente.');
    }
    return municipality;
  }

  Future<Position> current() => Geolocator.getCurrentPosition(
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.medium,
      timeLimit: Duration(seconds: 20),
    ),
  );
  Stream<Position> stream({
    required bool background,
  }) => Geolocator.getPositionStream(
    locationSettings: AndroidSettings(
      accuracy: LocationAccuracy.medium,
      distanceFilter: 1000,
      intervalDuration: const Duration(minutes: 2),
      foregroundNotificationConfig: background
          ? const ForegroundNotificationConfig(
              notificationTitle: 'Região automática ativa',
              notificationText:
                  'O IWOF PLUS acompanha mudanças de cidade para atualizar suas vagas.',
              notificationChannelName: 'Localização',
              setOngoing: true,
            )
          : null,
    ),
  );
}
