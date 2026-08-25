import 'package:flutter/material.dart';
import 'package:allo_service_pro/features/admin/domain/pending_pro_model.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:allo_service_pro/features/requests/application/request_store.dart';

// ─── Admin Credentials ──────────────────────────────────────────────────────
// ─── Reported-content model ──────────────────────────────────────────────────
class ReportModel {
  final String id;
  final String reportedBy;
  final String about;
  final String reason;
  final String date;
  bool resolved;

  ReportModel({
    required this.id,
    required this.reportedBy,
    required this.about,
    required this.reason,
    required this.date,
    this.resolved = false,
  });
}

// ─── Admin Store ─────────────────────────────────────────────────────────────
class AdminStore {
  AdminStore._();

  // Smart routing credentials used by the standard login screen.
  // (Demo-grade: production should authenticate against Firebase/backend.)
  static const String adminEmail = 'admin@alloservice.tn';
  static const String adminPassword = 'admin2026';

  static bool matchesAdmin(String email, String password) =>
      email == adminEmail && password == adminPassword;

  // Global stats
  static final totalUsers = ValueNotifier<int>(1240);
  static final totalPros = ValueNotifier<int>(347);
  static final totalRequests = ValueNotifier<int>(892);
  static final totalRevenue = ValueNotifier<double>(0.0);

  // Pending professionals
  static final pendingPros = ValueNotifier<List<PendingProModel>>([
    PendingProModel(
      id: 'pp_1',
      name: 'Mohamed Jaziri',
      phone: '+21620123456',
      professionFr: 'Plombier',
      professionAr: 'سبّاك',
      city: 'Tunis',
      submittedAt: '10/08/2026',
      docImage: null,
      status: 'pending',
    ),
    PendingProModel(
      id: 'pp_2',
      name: 'Sonia Belhaj',
      phone: '+21650987654',
      professionFr: 'Femme de ménage',
      professionAr: 'عاملة نظافة',
      city: 'Ariana',
      submittedAt: '10/08/2026',
      docImage: null,
      status: 'pending',
    ),
  ]);

  // Reports
  static final reports = ValueNotifier<List<ReportModel>>([
    ReportModel(
      id: 'r_1',
      reportedBy: 'Client Hedi B.',
      about: 'Pro: Karim Jebali',
      reason: 'Le professionnel ne s\'est pas présenté au rendez-vous.',
      date: '10/08/2026',
    ),
    ReportModel(
      id: 'r_2',
      reportedBy: 'Client Sara M.',
      about: 'Pro: Hatem Trabelsi',
      reason: 'Prix facturé différent du devis initial.',
      date: '09/08/2026',
    ),
    ReportModel(
      id: 'r_3',
      reportedBy: 'Client Nabil K.',
      about: 'Pro: Ahmed Ben Ali',
      reason: 'Travail non terminé, le pro est parti sans finir.',
      date: '08/08/2026',
    ),
  ]);

  static void setBadge(String id, String badge) {
    final list = List<PendingProModel>.from(pendingPros.value);
    final idx = list.indexWhere((p) => p.id == id);
    if (idx != -1) {
      list[idx] = list[idx].copyWith(badge: badge);
      pendingPros.value = list;
    }
  }

  static void resolveReport(String id) {
    final list = List<ReportModel>.from(reports.value);
    final idx = list.indexWhere((r) => r.id == id);
    if (idx != -1) {
      list[idx].resolved = true;
      reports.value = list;
    }
  }

  static int get pendingCount =>
      pendingPros.value.where((p) => p.status == 'pending').length;

  static int get openReportsCount =>
      reports.value.where((r) => !r.resolved).length;

  // Admin function to reset request acceptance and deduct tokens again
  static void resetRequestAcceptance(String requestId) {
    RequestStore.adminResetAcceptance(requestId);
  }

  // ─── Registration gatekeeping · PRO-XXXXX lifecycle ─────────────────

  static int _proSeq = 1;
  static const String _kRegistry = 'admin_pending_pros_json';
  static const String _kSeq = 'admin_pro_seq';

  /// Generates the next unique non-repeating identifier (PRO-00001…).
  static String _nextProCode() {
    final used = pendingPros.value.map((p) => p.proCode).toSet();
    var n = _proSeq;
    String code() => 'PRO-${n.toString().padLeft(5, '0')}';
    while (used.contains(code())) {
      n++;
    }
    _proSeq = n + 1;
    return code();
  }

  /// Registers a new professional: assigns the unique PRO-XXXXX code,
  /// defaults to `status = pending`, no tokens, no badges, not paid.
  static PendingProModel registerPro(PendingProModel draft) {
    final code = _nextProCode();
    final pro = draft.copyWith(
      proCode: code,
      status: 'pending',
      tokens: 0,
      isPaid: false,
      badges: const [],
    );
    pendingPros.value = [pro, ...pendingPros.value];
    persistToPrefs();
    return pro;
  }

  /// Admin approval: unlocks the account and grants 150 initial tokens.
  static void approvePro(String id, {String? badge}) {
    final idx = pendingPros.value.indexWhere((p) => p.id == id);
    if (idx == -1) return;
    final list = List<PendingProModel>.from(pendingPros.value);
    list[idx] = list[idx].copyWith(
      status: 'approved',
      tokens: 150,
      rejectionReason: null,
      badge: badge,
    );
    pendingPros.value = list;
    totalPros.value++;
    persistToPrefs();
  }

  /// Rejects with a visible reason; the Pro can re-upload proof later.
  static void rejectPro(String id, {String? reason}) {
    final idx = pendingPros.value.indexWhere((p) => p.id == id);
    if (idx == -1) return;
    final list = List<PendingProModel>.from(pendingPros.value);
    list[idx] = list[idx].copyWith(status: 'rejected', rejectionReason: reason);
    pendingPros.value = list;
    persistToPrefs();
  }

  /// Pro re-submits proof after a rejection — back to the review queue.
  static void resubmitProof(String id, {String? proofPath}) {
    final idx = pendingPros.value.indexWhere((p) => p.id == id);
    if (idx == -1) return;
    final list = List<PendingProModel>.from(pendingPros.value);
    list[idx] = list[idx].copyWith(
      status: 'pending',
      rejectionReason: null,
      docImage: proofPath,
    );
    pendingPros.value = list;
    persistToPrefs();
  }

  /// Manual token adjustment from the admin detail modal (+/-).
  static void adjustTokens(String id, int delta) {
    final idx = pendingPros.value.indexWhere((p) => p.id == id);
    if (idx == -1) return;
    final list = List<PendingProModel>.from(pendingPros.value);
    final next = (list[idx].tokens + delta).clamp(0, 9999);
    list[idx] = list[idx].copyWith(tokens: next);
    pendingPros.value = list;
    persistToPrefs();
  }

  /// Toggles the 30-day unlimited paid plan for a specific Pro.
  static void setPaid(String id, {required bool isPaid}) {
    final idx = pendingPros.value.indexWhere((p) => p.id == id);
    if (idx == -1) return;
    final list = List<PendingProModel>.from(pendingPros.value);
    list[idx] = list[idx].copyWith(isPaid: isPaid);
    pendingPros.value = list;
    persistToPrefs();
  }

  /// Adds or removes a manual badge (`verified` / `master` / `top_rated`).
  static void toggleBadge(String id, String badge) {
    final idx = pendingPros.value.indexWhere((p) => p.id == id);
    if (idx == -1) return;
    final list = List<PendingProModel>.from(pendingPros.value);
    final current = Set<String>.from(list[idx].badges);
    if (!current.add(badge)) current.remove(badge);
    list[idx] = list[idx].copyWith(badges: current.toList());
    pendingPros.value = list;
    persistToPrefs();
  }

  /// Pre-filled WhatsApp inquiry text for a given Pro.
  static String whatsappMessage({
    required String name,
    required String profession,
    required String proCode,
  }) =>
      'مرحبا، أنا $name — $profession.\n'
      'معرّفي المهني: $proCode\n'
      'أرجو مراجعة طلب تفعيل حسابي. 🙏';

  // ─── Local persistence (SharedPreferences) ──────────────────────────

  static Future<void> persistToPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _kRegistry,
        jsonEncode(pendingPros.value.map((p) => p.toJson()).toList()),
      );
      await prefs.setInt(_kSeq, _proSeq);
    } catch (_) {
      // Best-effort persistence.
    }
  }

  static Future<void> loadFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kRegistry);
      if (raw == null) return;
      final decoded = (jsonDecode(raw) as List)
          .map((e) => PendingProModel.fromJson(e as Map<String, dynamic>))
          .toList();
      pendingPros.value = decoded;
      _proSeq = (prefs.getInt(_kSeq) ?? decoded.length + 1).clamp(1, 999999);
    } catch (_) {
      // Corrupted registry: keep seeded demo data.
    }
  }
}
