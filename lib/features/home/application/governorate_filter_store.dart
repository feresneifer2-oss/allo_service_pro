import 'package:flutter/material.dart';

import '../../auth/application/user_store.dart';

/// Page-level home governorate filter.
///
/// Deliberately separate from the persistent user profile so that
/// "Toutes les wilayas" can clear it without mutating the saved account
/// data (the previous implementation wrote the filter into
/// [UserStore.set] which could never clear a value once set).
class GovernorateFilterStore {
  GovernorateFilterStore._();

  static final governorateAr = ValueNotifier<String?>(null);
  static final governorateFr = ValueNotifier<String?>(null);

  static bool _seeded = false;

  /// First build of the home page: default the filter to the profile's
  /// saved governorate (auto-detected or chosen at registration).
  static void ensureSeeded() {
    if (_seeded) return;
    _seeded = true;
    final u = UserStore.user.value;
    governorateAr.value = u?.governorateAr;
    governorateFr.value = u?.governorateFr;
  }

  static void set(String? ar, String? fr) {
    governorateAr.value = ar;
    governorateFr.value = fr;
  }

  static void clear() => set(null, null);

  /// Clears the filter AND the seed flag so the next login re-seeds it
  /// from the freshly restored profile / GPS detection (used on logout).
  static void reset() {
    _seeded = false;
    set(null, null);
  }
}
