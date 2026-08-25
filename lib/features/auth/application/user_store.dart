import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum UserRole { client, professional }

/// Verification lifecycle for professional accounts.
enum ProVerification {
  none,
  pending,
  approved,
  rejected;

  bool get isApproved => this == approved;
  bool get isPending => this == pending;
  bool get isRejected => this == rejected;
}

class UserModel {
  final String id;
  final String name;
  final String phone;
  final String? email;
  final UserRole? role;

  /// Unique professional identifier (PRO-XXXXX).
  final String? proCode;

  /// Proof-of-work photo path submitted at registration / re-upload.
  final String? proofPath;

  /// Verification lifecycle (professional accounts only).
  final ProVerification verificationStatus;

  /// Admin-written reason when the proof was rejected.
  final String? rejectionReason;

  const UserModel({
    required this.id,
    required this.name,
    required this.phone,
    this.email,
    this.role,
    this.proCode,
    this.proofPath,
    this.verificationStatus = ProVerification.none,
    this.rejectionReason,
  });

  bool get isProfessional => role == UserRole.professional;

  /// Professional accounts must pass admin verification before access.
  bool get needsVerificationGate =>
      isProfessional && !verificationStatus.isApproved;

  UserModel copyWith({
    UserRole? role,
    String? proCode,
    String? proofPath,
    ProVerification? verificationStatus,
    String? rejectionReason,
  }) =>
      UserModel(
        id: id,
        name: name,
        phone: phone,
        email: email,
        role: role ?? this.role,
        proCode: proCode ?? this.proCode,
        proofPath: proofPath ?? this.proofPath,
        verificationStatus:
            verificationStatus ?? this.verificationStatus,
        rejectionReason: rejectionReason ?? this.rejectionReason,
      );
}

class UserStore {
  UserStore._();

  static final user = ValueNotifier<UserModel?>(null);
  static final Map<String, _LocalAccount> _accounts = {};

  // ─── Local persistence keys ─────────────────────────────────────────
  static const String _kId = 'user_id';
  static const String _kName = 'user_name';
  static const String _kPhone = 'user_phone';
  static const String _kEmail = 'user_email';
  static const String _kRoleIdx = 'user_role_index';
  static const String _kProCode = 'user_pro_code';
  static const String _kProofPath = 'user_proof_path';
  static const String _kVerIdx = 'user_ver_status_index';
  static const String _kVerReason = 'user_ver_reason';

  static void set({
    required String name,
    required String phone,
    String? email,
    String? id,
    UserRole? role,
    String? proCode,
    String? proofPath,
    ProVerification? verificationStatus,
    String? rejectionReason,
  }) {
    user.value = UserModel(
      id: id ?? 'user_${DateTime.now().microsecondsSinceEpoch}',
      name: name,
      phone: phone,
      email: email,
      role: role,
      proCode: proCode ?? user.value?.proCode,
      proofPath: proofPath ?? user.value?.proofPath,
      verificationStatus: verificationStatus ??
          user.value?.verificationStatus ??
          ProVerification.none,
      rejectionReason: rejectionReason ?? user.value?.rejectionReason,
    );
    persistToPrefs();
  }

  /// Professional-side updates (proof re-upload / admin decision mirror).
  static void updateProVerification({
    required ProVerification status,
    String? reason,
    String? proofPath,
  }) {
    final current = user.value;
    if (current == null) return;
    user.value = current.copyWith(
      verificationStatus: status,
      rejectionReason: reason,
      proofPath: proofPath,
    );
    persistToPrefs();
  }

  // ─── Local persistence ──────────────────────────────────────────────

  static Future<void> persistToPrefs() async {
    try {
      final u = user.value;
      final prefs = await SharedPreferences.getInstance();
      if (u == null) return;

      await prefs.setString(_kId, u.id);
      await prefs.setString(_kName, u.name);
      await prefs.setString(_kPhone, u.phone);
      if (u.email != null) await prefs.setString(_kEmail, u.email!);
      if (u.role != null) await prefs.setInt(_kRoleIdx, u.role!.index);
      if (u.proCode != null) await prefs.setString(_kProCode, u.proCode!);
      if (u.proofPath != null) {
        await prefs.setString(_kProofPath, u.proofPath!);
      }
      await prefs.setInt(_kVerIdx, u.verificationStatus.index);
      if (u.rejectionReason != null) {
        await prefs.setString(_kVerReason, u.rejectionReason!);
      }
    } catch (_) {
      // Best-effort persistence.
    }
  }

  static Future<void> loadFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!prefs.containsKey(_kId)) return;

      final roleIdx = prefs.getInt(_kRoleIdx);
      final verIdx = prefs.getInt(_kVerIdx) ?? ProVerification.none.index;

      user.value = UserModel(
        id: prefs.getString(_kId)!,
        name: prefs.getString(_kName) ?? '',
        phone: prefs.getString(_kPhone) ?? '',
        email: prefs.getString(_kEmail),
        role: roleIdx == null
            ? null
            : UserRole
                .values[roleIdx.clamp(0, UserRole.values.length - 1)],
        proCode: prefs.getString(_kProCode),
        proofPath: prefs.getString(_kProofPath),
        verificationStatus: ProVerification.values[
            verIdx.clamp(0, ProVerification.values.length - 1)],
        rejectionReason: prefs.getString(_kVerReason),
      );
    } catch (_) {
      // Corrupted session: fall back to guest state.
    }
  }

  static bool register({
    required String name,
    required String phone,
    required String email,
    required String password,
  }) {
    final key = email.trim().toLowerCase();
    if (key.isEmpty || _accounts.containsKey(key)) return false;
    final account = _LocalAccount(name: name, phone: phone, password: password);
    _accounts[key] = account;
    set(name: name, phone: phone, email: key);
    return true;
  }

  static bool signIn({required String email, required String password}) {
    final key = email.trim().toLowerCase();
    final account = _accounts[key];
    if (account == null || account.password != password) return false;
    set(name: account.name, phone: account.phone, email: key);
    return true;
  }

  static void setRole(UserRole role) {
    final current = user.value;
    if (current != null) user.value = current.copyWith(role: role);
  }

  static void signOut() => user.value = null;

  static String get displayName {
    final n = user.value?.name.trim();
    if (n != null && n.isNotEmpty) return n.split(' ').first;
    return 'Utilisateur';
  }
}

class _LocalAccount {
  const _LocalAccount({
    required this.name,
    required this.phone,
    required this.password,
  });

  final String name;
  final String phone;
  final String password;
}
