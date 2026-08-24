import 'package:flutter/material.dart';
import 'package:allo_service_pro/features/admin/domain/pending_pro_model.dart';
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

  static void approvePro(String id, {String? badge}) {
    final list = List<PendingProModel>.from(pendingPros.value);
    final idx = list.indexWhere((p) => p.id == id);
    if (idx != -1) {
      list[idx] = list[idx].copyWith(
        status: 'approved',
        badge: badge ?? 'verified',
      );
      pendingPros.value = list;
      totalPros.value++;
    }
  }

  static void setBadge(String id, String badge) {
    final list = List<PendingProModel>.from(pendingPros.value);
    final idx = list.indexWhere((p) => p.id == id);
    if (idx != -1) {
      list[idx] = list[idx].copyWith(badge: badge);
      pendingPros.value = list;
    }
  }

  static void rejectPro(String id) {
    final list = List<PendingProModel>.from(pendingPros.value);
    final idx = list.indexWhere((p) => p.id == id);
    if (idx != -1) {
      list[idx] = list[idx].copyWith(status: 'rejected');
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
}
