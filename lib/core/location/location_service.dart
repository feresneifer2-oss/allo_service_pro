import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

import '../../features/auth/application/user_store.dart';
import '../../features/home/application/governorate_filter_store.dart';
import '../data/tunisian_locations.dart';

/// GPS auto-detection pipeline built on `geolocator` + `geocoding`.
///
/// Runs once at app launch ([init]) and resolves, best-effort:
/// 1. The user's Tunisian governorate → applied to the user profile and
///    seeded into the home page [GovernorateFilterStore].
/// 2. A human-readable street address → exposed via [resolvedAddress] so
///    the booking / request screens can prefill their address field.
///
/// Every failure path (GPS off, permission denied, geocoder unavailable)
/// degrades gracefully to manual entry — location is an enhancement,
/// never a blocker.
class LocationService {
  static final LocationService instance = LocationService._internal();
  factory LocationService() => instance;
  LocationService._internal();

  /// Street address resolved from GPS or null until a detection succeeds.
  /// Booking & request screens listen to this notifier and prefill their
  /// address field when it fires.
  static final resolvedAddress = ValueNotifier<String?>(null);

  /// Flips to true when a detection attempt hit a hard block (permission
  /// denied, GPS off, geocoder failure). UI layers may listen to it and
  /// show a clean "type your address manually" SnackBar. Resets to false
  /// on the next successful detection.
  static final manualFallbackNotice = ValueNotifier<bool>(false);

  /// Maximum age accepted from the OS-cached last-known position. Anything
  /// older is stale and rejected, so the address pre-fill never shows an
  /// outdated fix (threshold: 20 minutes).
  static const Duration cachedFixMaxAge = Duration(minutes: 20);

  bool _ranInit = false;

  /// One-shot startup hook (called from `main.dart` before `runApp`).
  Future<void> init() async {
    if (_ranInit) return;
    _ranInit = true;
    await ensureDetected();
  }

  /// Runs a detection pass when no address was resolved yet — e.g. the
  /// startup prompt was dismissed and the user just opened the booking
  /// screen. Safe to call repeatedly / fire-and-forget.
  Future<void> ensureDetected() async {
    if (resolvedAddress.value != null) return;
    try {
      final address = await detectAndApply();
      if (address != null && address.isNotEmpty) {
        resolvedAddress.value = address;
      }
    } catch (_) {
      // Manual fallback: the user types the address by hand.
    }
  }

  /// Detects the current position, maps it to a Tunisian governorate,
  /// applies it to the user profile and returns a readable address.
  Future<String?> detectAndApply() async {
    final position = await getCurrentLocation();
    if (position == null) {
      // Permission denied / GPS off → graceful manual-entry fallback.
      manualFallbackNotice.value = true;
      return null;
    }
    return _resolveAddress(position);
  }

  /// Explicit "My Location" tap with the full permission pipeline:
  /// 1. GPS switch check (off → prompt the system location settings)
  /// 2. `checkPermission()` → 3. `requestPermission()` (OS dialog) when
  /// denied → 4. `openAppSettings()` when permanently denied →
  /// 5. `getCurrentPosition()` + reverse geocoding.
  ///
  /// Returns the resolved address, or **null** when permission is
  /// denied/deniedForever or GPS is off — the caller must leave the
  /// address field EMPTY for manual typing and show the fallback
  /// SnackBar. NEVER returns a fake/hardcoded address.
  Future<String?> requestFreshLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        // Give the user a direct path to flip the GPS switch on, then
        // they can tap "My Location" again.
        await Geolocator.openLocationSettings();
        return null;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        // Triggers the native Android/iOS permission dialog.
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        // Only the app settings page can lift a permanent denial.
        await Geolocator.openAppSettings();
        return null;
      }
      if (permission == LocationPermission.denied) {
        return null;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );
      return _resolveAddress(position);
    } catch (_) {
      // Any plugin/geocoder failure → manual entry fallback.
      return null;
    }
  }

  /// Shared tail of both flows: reverse-geocode [position], apply the
  /// Tunisian governorate and build a readable street address.
  Future<String?> _resolveAddress(Position position) async {
    final placemarks = await getPlacemarkFromCoordinates(
      position.latitude,
      position.longitude,
    );
    if (placemarks.isEmpty) {
      manualFallbackNotice.value = true;
      return null;
    }
    manualFallbackNotice.value = false;
    final place = placemarks.first;

    // Map the geocoder output onto the local Tunisian governorate dataset
    // (most specific administrative label first).
    final candidates = <String>{
      place.administrativeArea ?? '',
      place.subAdministrativeArea ?? '',
      place.locality ?? '',
      place.subLocality ?? '',
    }..removeWhere((e) => e.trim().isEmpty);

    (String, String)? governorate;
    for (final candidate in candidates) {
      governorate = _matchGovernorate(candidate);
      if (governorate != null) break;
    }

    if (governorate != null) {
      _applyGovernorate(governorate.$1, governorate.$2);
    }

    // Readable street address for the booking / request prefill.
    final parts = <String>[
      place.street ?? place.name ?? '',
      place.subLocality ?? '',
      place.locality ?? '',
      governorate?.$2 ?? '',
    ].map((e) => e.trim()).where((e) => e.isNotEmpty).toSet().toList();
    return parts.isEmpty ? null : parts.join(', ');
  }

  Future<Position?> getCurrentLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return _lastKnownFallback();

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        // Smooth manual fallback: still try the OS-cached fix (stale
        // beats empty), otherwise the user types their address.
        return _lastKnownFallback();
      }

      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 12),
        ),
      );
    } catch (_) {
      return _lastKnownFallback();
    }
  }

  /// Fallback to the OS-cached last fix so the address still pre-fills
  /// when live GPS is unavailable or the permission prompt is dismissed.
  Future<Position?> _lastKnownFallback() async {
    try {
      final pos = await Geolocator.getLastKnownPosition();
      if (pos == null) return null;
      // Freshness gate: a cached fix older than [cachedFixMaxAge] is treated
      // as stale and discarded — the caller falls back to manual entry rather
      // than pre-filling an outdated address.
      final age = DateTime.now().difference(pos.timestamp);
      if (age > cachedFixMaxAge) return null;
      return pos;
    } catch (_) {
      return null;
    }
  }

  Future<List<Placemark>> getPlacemarkFromCoordinates(
      double latitude, double longitude) async {
    try {
      return await Geocoding().placemarkFromCoordinates(latitude, longitude);
    } catch (e) {
      return [];
    }
  }

  /// Maps a geocoder label (governorate or city, FR or AR) to the local
  /// Tunisian dataset. Returns `(governorateAr, governorateFr)` or null.
  (String, String)? _matchGovernorate(String label) {
    final q = _normalize(label);
    if (q.isEmpty) return null;
    for (final loc in TunisianLocations.locations) {
      if (_normalize(loc.governorateFr) == q || loc.governorateAr == label) {
        return (loc.governorateAr, loc.governorateFr);
      }
      for (final city in loc.cities) {
        if (_normalize(city.fr) == q || city.ar == label) {
          return (loc.governorateAr, loc.governorateFr);
        }
      }
    }
    return null;
  }

  String _normalize(String value) {
    var v = value.trim().toLowerCase();
    const accents = {
      'é': 'e',
      'è': 'e',
      'ê': 'e',
      'à': 'a',
      'â': 'a',
      'î': 'i',
      'ï': 'i',
      'ô': 'o',
      'û': 'u',
      'ù': 'u',
      'ç': 'c',
    };
    accents.forEach((accent, plain) => v = v.replaceAll(accent, plain));
    return v;
  }

  /// Writes the detected governorate into the user profile WITHOUT
  /// overwriting an explicit choice made at registration, and refreshes
  /// the home page filter so recommendations match immediately.
  void _applyGovernorate(String ar, String fr) {
    final user = UserStore.user.value;
    if (user != null &&
        (user.governorateAr == null || user.governorateFr == null)) {
      UserStore.user.value =
          user.copyWith(governorateAr: ar, governorateFr: fr);
      UserStore.persistToPrefs();
    }
    GovernorateFilterStore.set(ar, fr);
  }
}
