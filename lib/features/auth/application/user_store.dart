import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:allo_service_pro/features/chat/application/chat_store.dart';
import 'package:allo_service_pro/features/home/application/governorate_filter_store.dart';
import 'package:allo_service_pro/features/notifications/application/notification_store.dart';
import 'package:allo_service_pro/features/pro_dashboard/application/pro_profile_store.dart';
import 'package:allo_service_pro/shared/validators.dart';

import 'package:allo_service_pro/features/pro_dashboard/application/subscription_store.dart';
import 'package:allo_service_pro/features/requests/application/request_store.dart';

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

  /// Detected governorate (auto or manual).
  final String? governorateAr;
  final String? governorateFr;

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
    this.governorateAr,
    this.governorateFr,
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
    String? governorateAr,
    String? governorateFr,
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
        governorateAr: governorateAr ?? this.governorateAr,
        governorateFr: governorateFr ?? this.governorateFr,
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

  /// Persisted client registry — feeds the admin "Clients" tab and the
  /// KPI "Total Clients". Entries survive restarts (SharedPreferences).
  static final registeredClients =
      ValueNotifier<List<UserModel>>([]);

  // --- Local persistence keys -----------------------------------------
  static const String _kId = 'user_id';
  static const String _kName = 'user_name';
  static const String _kPhone = 'user_phone';
  static const String _kEmail = 'user_email';
  static const String _kRoleIdx = 'user_role_index';
  static const String _kProCode = 'user_pro_code';
  static const String _kProofPath = 'user_proof_path';
  static const String _kVerIdx = 'user_ver_status_index';
  static const String _kVerReason = 'user_ver_reason';
  static const String _kGovernorateAr = 'user_governorate_ar';
  static const String _kGovernorateFr = 'user_governorate_fr';
  // Explicit auto-login keys (written at login/register, wiped at signOut).
  static const String _kIsLoggedIn = 'is_logged_in';
  static const String _kUserRole = 'user_role';

  /// Canonical persisted role string: 'client' or 'professionnel'.
  static String _roleKey(UserRole role) =>
      role == UserRole.professional ? 'professionnel' : 'client';

  static UserRole? _roleFromKey(String? key) {
    switch (key) {
      case 'client':
        return UserRole.client;
      case 'professionnel':
        return UserRole.professional;
      default:
        return null;
    }
  }

  /// Unified session resolution for the splash screen — the SINGLE source of
  /// truth for auto-login routing, replacing the old multi-key / duplicated
  /// auth reads in the splash widget. Exactly one consolidated read happens
  /// here (this method), and it trusts the state already hydrated at startup
  /// (`loadFromPrefs`) otherwise.
  ///
  /// The persisted role key is authoritative because the admin sign-in lives
  /// OUTSIDE the client/professional [UserRole] enum ('admin' is a string
  /// marker). The key is written at every login (set / admin sign-in) and
  /// removed by [signOutAndReset].
  ///
  /// Returns the route key — 'admin' | 'professionnel' | 'client' — or null
  /// when the device has no active session (guest / signed out).
  static Future<String?> checkInitialSession() async {
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool(_kIsLoggedIn) ?? false)) return null;
    final roleKey = prefs.getString(_kUserRole);
    if (roleKey != null && roleKey.isNotEmpty) return roleKey;
    // Legacy sessions saved before the role key existed: derive the route
    // from the in-memory session hydrated at startup.
    final u = user.value;
    if (u == null || u.role == null) return null;
    return _roleKey(u.role!);
  }

  static void set({
    required String name,
    required String phone,
    String? email,
    String? id,
    UserRole? role,
    String? proCode,
    String? governorateAr,
    String? governorateFr,
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
      // Explicit semantics: passing null CLEARS the governorate (the old
      // `?? user.value?...` merge made "all governorates" unselectable).
      // Blank strings are normalized to null as well so no empty entry can
      // ever reach the model and render blank labels in the UI.
      governorateAr: _cleanGov(governorateAr),
      governorateFr: _cleanGov(governorateFr),
      proofPath: proofPath ?? user.value?.proofPath,
      verificationStatus: verificationStatus ?? user.value?.verificationStatus ?? ProVerification.none,
      rejectionReason: rejectionReason ?? user.value?.rejectionReason,
    );
    persistToPrefs();
  }

  // --- Governorate sanitization -----------------------------------------
  /// Treats null / empty / whitespace-only governorate values as null so a
  /// blank selection can never be stored or rendered.
  static String? _cleanGov(String? raw) {
    if (raw == null) return null;
    final v = raw.trim();
    return v.isEmpty ? null : v;
  }

  /// Writes a prefs string only when meaningful; otherwise strips the key so
  /// stale blank entries are removed instead of lingering as empty strings.
  static Future<void> _writeOrRemove(
    SharedPreferences prefs,
    String key,
    String? value,
  ) async {
    final v = _cleanGov(value);
    if (v == null) {
      await prefs.remove(key);
    } else {
      await prefs.setString(key, v);
    }
  }

  // --- Local persistence ----------------------------------------------
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
      // Null OR blank → the key is stripped entirely (never an empty
      // string) so stale blank entries cannot survive a profile update.
      await _writeOrRemove(prefs, _kGovernorateAr, u.governorateAr);
      await _writeOrRemove(prefs, _kGovernorateFr, u.governorateFr);
      if (u.proofPath != null) await prefs.setString(_kProofPath, u.proofPath!);
      await prefs.setInt(_kVerIdx, u.verificationStatus.index);
      if (u.rejectionReason != null) await prefs.setString(_kVerReason, u.rejectionReason!);
      // Auto-login markers: the session survives restarts and the role
      // drives the direct routing (client → ClientShell, professionnel →
      // ProShell) performed by the splash screen.
      await prefs.setBool(_kIsLoggedIn, true);
      if (u.role != null) {
        await prefs.setString(_kUserRole, _roleKey(u.role!));
      }
    } catch (_) {
      // Best-effort persistence.
    }
  }

  static Future<void> loadFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Restore the credential registry FIRST — it must load even when no
      // session is active (fresh restart before any email/password login).
      final rawAccounts = prefs.getString(_kAccounts);
      if (rawAccounts != null) {
        final decoded = jsonDecode(rawAccounts) as List;
        _accounts.clear();
        for (final e in decoded) {
          final m = e as Map<String, dynamic>;
          final emailKey =
              ((m['email'] as String?) ?? '').trim().toLowerCase();
          if (emailKey.isEmpty) continue;
          final verIdx =
              (m['verIdx'] as int?) ?? ProVerification.none.index;
          _accounts[emailKey] = _LocalAccount(
            name: (m['name'] as String?) ?? '',
            phone: (m['phone'] as String?) ?? '',
            password: (m['password'] as String?) ?? '',
            role: _roleFromKey(m['role'] as String?),
            proCode: m['proCode'] as String?,
            verificationStatus: ProVerification
                .values[verIdx
                    .clamp(0, ProVerification.values.length - 1)],
          );
        }
      }
    } catch (_) {
      // Corrupted registry → start empty.
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!prefs.containsKey(_kId)) return;

      final roleIdx = prefs.getInt(_kRoleIdx);
      final verIdx = prefs.getInt(_kVerIdx) ?? ProVerification.none.index;
      // Blank values saved by legacy versions are normalized to null so the
      // UI never renders empty governorate chips after a restart.
      final governorateAr = _cleanGov(prefs.getString(_kGovernorateAr));
      final governorateFr = _cleanGov(prefs.getString(_kGovernorateFr));
      // Auto-login: explicit 'client' / 'professionnel' marker, with the
      // legacy role index as fallback for sessions saved before this key.
      final role = _roleFromKey(prefs.getString(_kUserRole)) ??
          (roleIdx == null
              ? null
              : UserRole.values[roleIdx.clamp(0, UserRole.values.length - 1)]);

      user.value = UserModel(
        id: prefs.getString(_kId)!,
        name: prefs.getString(_kName) ?? '',
        phone: prefs.getString(_kPhone) ?? '',
        email: prefs.getString(_kEmail),
        role: role,
        proCode: prefs.getString(_kProCode),
        governorateAr: governorateAr,
        governorateFr: governorateFr,
        proofPath: prefs.getString(_kProofPath),
        verificationStatus: ProVerification.values[verIdx.clamp(0, ProVerification.values.length - 1)],
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
    // Defense-in-depth: normalize the phone HERE as well so any caller path
    // (screens, future imports) persists a canonical 8-digit number and
    // account lookups never mismatch on formatting variants ("+216 22 123
    // 456" and "22123456" are the same subscriber).
    final normalizedPhone = AppValidators.normalizePhone(phone);
    final account =
        _LocalAccount(name: name, phone: normalizedPhone, password: password);
    _accounts[key] = account;
    _persistAccounts();
    set(name: name, phone: normalizedPhone, email: key);
    _registerClient(name: name, phone: normalizedPhone, email: key);
    return true;
  }

  /// Registers the new account in the persisted client registry
  /// (deduplicated by id) and persists it.
  static void _registerClient({
    required String name,
    required String phone,
    required String email,
  }) {
    final client = UserModel(
      id: user.value?.id ?? email,
      name: name,
      phone: phone,
      email: email,
      role: UserRole.client,
    );
    final exists = registeredClients.value.any((c) => c.id == client.id);
    if (!exists) {
      registeredClients.value = [client, ...registeredClients.value];
    }
    _persistClients();
  }

  static Future<void> _persistClients() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_registered_clients',
          jsonEncode(registeredClients.value.map(_clientToJson).toList()));
    } catch (_) {
      // Best-effort persistence.
    }
  }

  static Map<String, dynamic> _clientToJson(UserModel c) => {
        'id': c.id,
        'name': c.name,
        'phone': c.phone,
        'email': c.email,
      };

  static UserModel _clientFromJson(Map<String, dynamic> j) => UserModel(
        id: j['id'] as String,
        name: (j['name'] as String?) ?? '',
        phone: (j['phone'] as String?) ?? '',
        email: j['email'] as String?,
        role: UserRole.client,
      );

  /// Restores the persisted client registry (called at startup).
  static Future<void> loadRegisteredClients() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('user_registered_clients');
      if (raw == null) return;
      final decoded = (jsonDecode(raw) as List)
          .map((e) => _clientFromJson(e as Map<String, dynamic>))
          .toList();
      registeredClients.value = decoded;
    } catch (_) {
      // Corrupted registry → keep current state.
    }
  }

  static bool signIn({required String email, required String password}) {
    final key = email.trim().toLowerCase();
    final account = _accounts[key];
    if (account == null || account.password != password) return false;
    // Restore the FULL profile (role · PRO code · verification state) from
    // the persisted credential record — a returning pro lands straight on
    // ProShell instead of replaying onboarding / registration.
    set(
      name: account.name,
      phone: account.phone,
      email: key,
      role: account.role,
      proCode: account.proCode,
      verificationStatus: account.verificationStatus,
    );
    return true;
  }

  static void setRole(UserRole role) {
    final current = user.value;
    if (current != null) {
      user.value = current.copyWith(role: role);
      // Sync the credential record too, so a later email/password login
      // restores the role instead of re-running the onboarding flow.
      final emailKey = current.email?.trim().toLowerCase();
      final account =
          (emailKey == null) ? null : _accounts[emailKey];
      if (emailKey != null && account != null) {
        _accounts[emailKey] = _LocalAccount(
          name: account.name,
          phone: account.phone,
          password: account.password,
          role: role,
          proCode: account.proCode,
          verificationStatus: account.verificationStatus,
        );
        _persistAccounts();
      }
      // Persist immediately so a restart routes straight to the right shell.
      persistToPrefs();
    }
  }

  /// Binds the professional identity (PRO-XXXXX + verification state) to the
  /// credential record of the CURRENT session user. Called when a pro submits
  /// the registration form — the record is flushed to SharedPreferences so a
  /// returning pro's email/password login restores the full pro profile.
  static void bindProAccount({
    required String? proCode,
    required ProVerification verificationStatus,
  }) {
    final key = user.value?.email?.trim().toLowerCase();
    if (key == null || !_accounts.containsKey(key)) return;
    final account = _accounts[key]!;
    _accounts[key] = _LocalAccount(
      name: account.name,
      phone: account.phone,
      password: account.password,
      role: UserRole.professional,
      proCode: proCode ?? account.proCode,
      verificationStatus: verificationStatus,
    );
    _persistAccounts();
  }

  /// Admin-side sync: updates the verification state of every account whose
  /// phone matches [phone] (the admin approves / rejects / re-queues a pro —
  /// the credential record must follow so the next login reflects it).
  static void syncAccountVerificationByPhone(
    String phone, {
    required ProVerification status,
  }) {
    final matches = _accounts.entries
        .where((e) => e.value.phone.trim() == phone.trim())
        .toList();
    for (final e in matches) {
      final a = e.value;
      _accounts[e.key] = _LocalAccount(
        name: a.name,
        phone: a.phone,
        password: a.password,
        role: a.role ?? UserRole.professional,
        proCode: a.proCode,
        verificationStatus: status,
      );
    }
    if (matches.isNotEmpty) _persistAccounts();
  }

  // --- Credential registry persistence (SharedPreferences) --------------
  static const String _kAccounts = 'user_accounts_json';

  /// Flushes the full credential registry (email · password · role ·
  /// PRO code · verification state) so credentials survive app restarts.
  static Future<void> _persistAccounts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = _accounts.entries
          .map((e) => <String, dynamic>{
                'email': e.key,
                'name': e.value.name,
                'phone': e.value.phone,
                'password': e.value.password,
                'role': e.value.role == null ? null : _roleKey(e.value.role!),
                'proCode': e.value.proCode,
                'verIdx': e.value.verificationStatus.index,
              })
          .toList();
      await prefs.setString(_kAccounts, jsonEncode(list));
    } catch (_) {
      // Storage unavailable — in-memory registry keeps working.
    }
  }

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

  /// Signs the user out and wipes every persisted session key so a restart
  /// lands on the welcome screen instead of silently restoring the session.
  static Future<void> signOut() async {
    user.value = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kId);
      await prefs.remove(_kName);
      await prefs.remove(_kPhone);
      await prefs.remove(_kEmail);
      await prefs.remove(_kRoleIdx);
      await prefs.remove(_kProCode);
      await prefs.remove(_kProofPath);
      await prefs.remove(_kVerIdx);
      await prefs.remove(_kVerReason);
      await prefs.remove(_kGovernorateAr);
      await prefs.remove(_kGovernorateFr);
      // Auto-login markers: wiped so the restart lands back on the
      // welcome / onboarding flow instead of a restored session.
      await prefs.remove(_kIsLoggedIn);
      await prefs.remove(_kUserRole);
    } catch (_) {
      // Best-effort cleanup.
    }
  }

  /// Full logout for every role (client / professionnel / admin):
  ///
  /// 1. Wipes the persisted user session — profile, tokens AND the
  ///    auto-login flags (`is_logged_in`, `user_role`) — so a cold app
  ///    restart can NEVER silently restore the previous session.
  /// 2. Resets every session-scoped local store back to its defaults
  ///    (subscription, pro profile, chats, orders, notifications,
  ///    home governorate filter).
  static Future<void> signOutAndReset() async {
    await signOut();
    await SubscriptionStore.reset();
    await ProProfileStore.reset();
    ChatStore.reset();
    RequestStore.reset();
    NotificationStore.clear();
    GovernorateFilterStore.reset();
  }

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
    this.role,
    this.proCode,
    this.verificationStatus = ProVerification.none,
  });

  final String name;
  final String phone;
  final String password;

  /// Stored role — a returning login with a stored role skips onboarding
  /// and routes straight to the matching shell.
  final UserRole? role;

  /// PRO-XXXXX identifier bound at pro registration.
  final String? proCode;

  /// Verification lifecycle snapshot, synced by the admin panel.
  final ProVerification verificationStatus;
}


