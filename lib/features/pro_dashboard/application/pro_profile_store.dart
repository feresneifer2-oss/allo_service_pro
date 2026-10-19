import 'dart:async';

import 'package:flutter/material.dart';
import 'package:allo_service_pro/core/data/services_catalog.dart';
import 'package:allo_service_pro/core/models/request_status.dart';
import 'package:allo_service_pro/features/requests/models/service_request.dart';
import 'package:allo_service_pro/core/network/connectivity_store.dart';
import 'package:allo_service_pro/core/queue/offline_queue.dart';
import 'package:allo_service_pro/core/queue/queued_action.dart';
import 'package:allo_service_pro/features/auth/application/supabase_auth_service.dart';
import 'package:allo_service_pro/features/auth/application/user_store.dart';
import 'package:allo_service_pro/features/pro_dashboard/application/subscription_store.dart';
import 'package:allo_service_pro/features/pro_dashboard/data/pro_availability_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ProProfileStore {
  ProProfileStore._();

  /// The professional's PERSISTENT availability state — "accepts new service
  /// requests".
  ///
  /// Not a presence/connection indicator: the value is a business decision, it
  /// is written to the `pro_availability` row of the signed-in account and it
  /// survives a force-close, a kill or a restart. [ValueNotifier] is kept as
  /// the UI contract (every existing listener — the dashboard's green/red dot,
  /// `ProfessionalProfileScreen` — keeps reacting in the very next frame).
  static final isAvailable = ValueNotifier<bool>(true);
  static final tokens = ValueNotifier<int>(0);
  // Phase A: honest defaults — REAL stats come from the loaded orders via
  // [computeFromOrders] (a new pro has 0 completed services and no rating).
  static final completedServices = ValueNotifier<int>(0);
  static final rating = ValueNotifier<double>(0.0);

  static String? professionFr;
  static String? professionAr;
  // Phase A: a new pro configured NO service zones yet — the setup screen
  // starts unselected instead of pre-ticking Ariana/Tunis.
  static List<String> zones = [];

  static final selectedSpecialties = ValueNotifier<List<ServiceItem>>([]);
  static final pricingType =
      ValueNotifier<String>('fixed'); // 'hourly', 'fixed', 'quote'
  static final priceFrom = ValueNotifier<int>(50);
  static final workImages = ValueNotifier<List<String>>([]);

  // Phase 4: honest defaults — no fake stats for a new pro.
  static final punctualityRate = ValueNotifier<double>(0.0);
  static final acceptanceRate = ValueNotifier<double>(0.0);
  static final responseTimeMin = ValueNotifier<int>(0);
  static final hasBrandedUniform = ValueNotifier<bool>(false);

  // Service zones (governorates) — empty until the pro configures them
  // (Phase A: no pre-selected seed).
  static final serviceZones = ValueNotifier<List<String>>([]);

  /// True once the account has ACTUALLY consumed part of its supply (an order
  /// accepted on the trial plan spent real tokens). The ProShell lock uses
  /// this so a brand-new trial account never gets locked just because its
  /// balance was manually adjusted to 0 — only a trial that has been USED and
  /// ran dry is shown the "Tokens Épuisés" paywall.
  static final tokensConsumed = ValueNotifier<bool>(false);

  // Token management

  /// Unlimited mode: paid subscribers never spend tokens.
  static bool get hasUnlimitedTokens =>
      SubscriptionStore.isPaidSubscriber.value;

  // ─── Local persistence (SharedPreferences) ──────────────────────────
  static const String _kTokens = 'pro_tokens';
  static const String _kTokensConsumed = 'pro_tokens_consumed';

  /// Locally cached availability flag. The AUTHORITATIVE copy lives in the
  /// `pro_availability` row (Supabase is the single source of truth); this key
  /// is the OFFLINE-FIRST mirror that lets the dashboard restore the last known
  /// state on the very first frame, before any network round-trip resolves.
  static const String _kIsAvailable = 'pro_availability';

  /// Writes the token balance, the consumption flag AND the availability
  /// state to SharedPreferences so they survive app restarts exactly alike.
  ///
  /// Failures are swallowed so gameplay mutations never break because
  /// storage happens to be unavailable.
  static Future<void> persistToPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kTokens, tokens.value);
      await prefs.setBool(_kTokensConsumed, tokensConsumed.value);
      await prefs.setBool(_kIsAvailable, isAvailable.value);
    } catch (_) {
      // Storage unavailable (e.g. tests without platform binding): ignore.
    }
  }

  /// Restores the persisted token balance, consumption flag and availability
  /// state at app startup.
  ///
  /// Falls back to the default balance 0 — the server (professionals.tokens)
  /// grants 150 on admin approval (Phase B).
  /// The consumption flag is restored BEFORE the balance so any listener
  /// fired by the balance update already observes the final state.
  ///
  /// AVAILABILITY FIRST AND INDEPENDENTLY of the token keys: a pro who toggled
  /// themselves offline and force-closed the app must come back OFFLINE, and
  /// that must not depend on whether a token balance happened to be persisted.
  /// Nothing is written when no flag was ever saved — the default (`true`)
  /// stands, so a fresh install is available, never silently hidden.
  static Future<void> loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.containsKey(_kIsAvailable)) {
      final saved = prefs.getBool(_kIsAvailable);
      if (saved != null) {
        isAvailable.value = saved;
      }
    }
    if (!prefs.containsKey(_kTokens)) return;
    if (prefs.containsKey(_kTokensConsumed)) {
      tokensConsumed.value = prefs.getBool(_kTokensConsumed) ?? false;
    }
    tokens.value = prefs.getInt(_kTokens) ?? 0;
  }

  // ─── Persistent availability (Supabase `pro_availability`) ──────────────
  //
  // DATA FLOW (one value, three layers — Postgres is the source of truth):
  //   1. the notifier is flipped SYNCHRONOUSLY, so the dashboard indicator
  //      repaints in the very next frame (no await sits between the tap and
  //      the flip — the existing Switch contract);
  //   2. the offline-first mirror key is written, so a force-close / kill
  //      restores the value with NO network at all ([loadFromPrefs]);
  //   3. the row is upserted on Supabase — or, when the device is offline,
  //      enqueued and replayed by [OfflineQueue] on reconnection.
  //
  // The REMOTE→LOCAL direction (the row restored at session start, or a value
  // another device wrote) enters through [applyRemoteAvailability], fed by
  // `ProAvailabilityStore.hydrateFromSupabase()` — the single ingress, which
  // never echoes the value back and therefore cannot loop.

  /// Toggles "accepts new requests" for the signed-in professional.
  ///
  /// Persists locally, then mirrors the choice to the `pro_availability` row
  /// (queued when the device is offline). The returned future settles the
  /// durable work; the UI may fire-and-forget — the notifier already carries
  /// the new value.
  static Future<void> setAvailability(bool value) async {
    if (isAvailable.value != value) {
      isAvailable.value = value;
    }
    await _persistAvailability(value);
    await _pushAvailability(value);
  }

  /// REALTIME / SESSION-START INGRESS of the pro's OWN row.
  ///
  /// Adopts a value this device did not produce (another device toggled, or the
  /// backend answered the boot hydration). Deliberately does NOT write back:
  /// the value already lives in Postgres, and echoing it would be both a
  /// pointless round-trip and a potential ping-pong with the same ingress.
  static void applyRemoteAvailability(bool value) {
    if (isAvailable.value == value) return;
    isAvailable.value = value;
    unawaited(_persistAvailability(value)); // survive a force-close offline
  }

  /// Offline-first mirror write (never throws: storage may be unavailable).
  static Future<void> _persistAvailability(bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kIsAvailable, value);
    } catch (_) {
      // Storage unavailable — the in-memory + remote layers still hold it.
    }
  }

  /// Mirrors [value] to the `pro_availability` row of the signed-in account.
  ///
  /// Three outcomes: no remote identity → nothing to mirror (local-only build
  /// or signed-out device); offline / unconfigured / failed → ENQUEUED, so the
  /// queue's connectivity listener replays it later; otherwise applied.
  static Future<void> _pushAvailability(bool value) async {
    final proId = SupabaseAuthService.currentUserId;
    if (proId == null) return;
    final proCode = UserStore.user.value?.proCode;
    if (!ConnectivityStore.isOnline.value ||
        !ProAvailabilityRepository.isConfigured) {
      await _enqueueAvailability(proId, proCode, value);
      return;
    }
    final applied = await ProAvailabilityRepository.upsertAvailability(
      proId: proId,
      proCode: proCode,
      isAvailable: value,
    );
    if (applied) {
      // Phase 7-3: drop any stale queue entry for this id — the upsert just
      // superseded it; keeping it would replay a wrong value later.
      await OfflineQueue.removeById('pro_availability_$proId');
    } else {
      await _enqueueAvailability(proId, proCode, value);
    }
  }

  /// Builds the queued action for an availability toggle.
  ///
  /// The id is DERIVED from the professional (`pro_availability_<uid>`) — never
  /// random — so the queue holds at most ONE pending toggle per account:
  /// [OfflineQueue.replace] re-keys the existing entry in place, and THAT is
  /// what guarantees the replayed value is the last one the user chose.
  ///
  /// Exposed for the offline-replay tests; the production path is
  /// [setAvailability].
  @visibleForTesting
  static QueuedAction buildAvailabilityAction({
    required String proId,
    String? proCode,
    required bool isAvailable,
    int? createdAtMs,
  }) {
    final code = proCode?.trim() ?? '';
    return QueuedAction(
      id: 'pro_availability_$proId',
      type: QueuedActionType.updateProAvailability,
      payload: <String, dynamic>{
        'proId': proId,
        if (code.isNotEmpty) 'proCode': code,
        'isAvailable': isAvailable,
      },
      createdAtMs: createdAtMs ?? DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// Queues the LAST availability action of [proId].
  ///
  /// ONE entry per professional, re-keyed in place: toggling offline↔online
  /// five times while offline must not stack five actions — the queue holds
  /// "what still has to be sent", not a journal, and the FINAL state is the
  /// latest user action. The replay is an idempotent UPSERT, so sending only
  /// the newest value is equivalent while keeping the queue bounded.
  static Future<void> _enqueueAvailability(
    String proId,
    String? proCode,
    bool value,
  ) async {
    final action = buildAvailabilityAction(
      proId: proId,
      proCode: proCode,
      isAvailable: value,
    );
    final alreadyQueued = OfflineQueue.pending.value.any(
      (a) => a.id == action.id,
    );
    if (alreadyQueued) {
      // Re-key the existing entry (same id ⇒ same FIFO slot) and persist the
      // rewrite once, so the superseded value can never be replayed later.
      OfflineQueue.replace(action);
      await OfflineQueue.persistSerially();
      return;
    }
    await OfflineQueue.enqueue(action);
  }

  static Future<bool> deductTokens(int amount) async {
    if (hasUnlimitedTokens) return true;
    if (tokens.value >= amount) {
      // Flag is flipped BEFORE the balance change so every listener woken
      // by the balance notification already sees the fresh consumed state.
      tokensConsumed.value = true; // real usage: depletion may lock later
      tokens.value -= amount;
      await persistToPrefs();
      return true;
    }
    return false;
  }

  static Future<void> addTokens(int amount) async {
    tokens.value += amount;
    await persistToPrefs();
  }

  static void updateServiceZones(List<String> zones) {
    serviceZones.value = zones;
  }

  /// Derives the pro's REAL stats from the loaded orders (Phase A).
  ///
  ///   • [completedServices] = count of orders whose status is `completed`;
  ///   • [rating] = mean of the non-null order ratings, else 0.0 (no rating
  ///     yet — the UI renders the dash placeholder, never a fake 4.9).
  ///
  /// Called whenever orders are (re)loaded — notably at the end of
  /// [RequestStore.hydrateFromSupabase] — so the dashboard and profile
  /// badges always mirror the backend, not a seed.
  static void computeFromOrders(List<ServiceRequest> orders) {
    final done = orders.where((o) => o.status == RequestStatus.completed);
    completedServices.value = done.length;
    final rated = done.where((o) => o.rating != null).map((o) => o.rating!);
    rating.value =
        rated.isEmpty ? 0.0 : rated.reduce((a, b) => a + b) / rated.length;
  }

  /// Restores the default trial profile state and clears the persisted
  /// token balance (used on logout). EVERY mutable field, notifier and
  /// cached property is reset so a previously logged-in professional can
  /// never leak data (tokens, pricing, photos, ratings, zones, badges…)
  /// into the next account on this device.
  static Future<void> reset() async {
    // Phase B: default 0 — server grants 150 on admin approval.
    tokens.value = 0;
    isAvailable.value = true;
    // Phase A: honest logout defaults — never the demo seeds.
    completedServices.value = 0;
    rating.value = 0.0;
    selectedSpecialties.value = [];
    pricingType.value = 'fixed';
    priceFrom.value = 50;
    workImages.value = [];
    punctualityRate.value = 0.0;
    acceptanceRate.value = 0.0;
    responseTimeMin.value = 0;
    hasBrandedUniform.value = false;
    // Phase A: zones reset to EMPTY — the previous Ariana/Tunis seed made
    // every new account look pre-configured.
    serviceZones.value = [];
    zones = [];
    professionFr = null;
    professionAr = null;
    tokensConsumed.value = false; // fresh trial: manual 0 never locks
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kTokens);
      await prefs.remove(_kTokensConsumed);
      // The LOCAL availability cache is cleared with the rest of the account
      // state (the next account must not inherit it). The `pro_availability`
      // ROW is deliberately left untouched: it describes the professional's
      // business choice, not a session — signing out on this device must never
      // flip them "unavailable" for the clients already looking at their card.
      await prefs.remove(_kIsAvailable);
    } catch (_) {
      // Best-effort cleanup.
    }
  }
}
