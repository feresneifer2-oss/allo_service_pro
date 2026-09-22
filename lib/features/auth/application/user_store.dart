import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:allo_service_pro/core/security/hashing.dart';
import 'package:allo_service_pro/features/admin/data/admin_auth_repository.dart';
import 'package:allo_service_pro/features/anti_abuse/application/anti_abuse_store.dart';
import 'package:allo_service_pro/features/auth/application/supabase_auth_service.dart';
import 'package:allo_service_pro/features/chat/application/chat_store.dart';
import 'package:allo_service_pro/features/home/application/governorate_filter_store.dart';
import 'package:allo_service_pro/features/notifications/application/notification_store.dart';
import 'package:allo_service_pro/features/pro_dashboard/application/pro_profile_store.dart';
import 'package:allo_service_pro/features/requests/application/request_store.dart';
import 'package:allo_service_pro/shared/validators.dart';

import 'package:allo_service_pro/features/pro_dashboard/application/subscription_store.dart';

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

  /// Selfie-with-document photo path captured at registration.
  final String? selfiePath;

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
    this.selfiePath,
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
    String? selfiePath,
    ProVerification? verificationStatus,
    String? rejectionReason,
    // Explicit-clear flags: passing `proofPath: null` alone can NOT clear
    // the field because of the `?? this.proofPath` merge below (null is
    // ambiguous between "not passed" and "clear it"). Setting these flags
    // to true forces the field to null regardless of the nullable arg.
    // `proCode` / `rejectionReason` need the same treatment: a sign-in that
    // binds a client account (proCode == null, no reason) must be able to
    // strip another account's PRO code / rejection text instead of merging
    // it via `?? this.…`.
    bool clearProofPath = false,
    bool clearSelfiePath = false,
    bool clearProCode = false,
    bool clearRejectionReason = false,
  }) =>
      UserModel(
        id: id,
        name: name,
        phone: phone,
        email: email,
        role: role ?? this.role,
        proCode: clearProCode ? null : (proCode ?? this.proCode),
        governorateAr: governorateAr ?? this.governorateAr,
        governorateFr: governorateFr ?? this.governorateFr,
        proofPath: clearProofPath ? null : (proofPath ?? this.proofPath),
        selfiePath: clearSelfiePath ? null : (selfiePath ?? this.selfiePath),
        verificationStatus: verificationStatus ?? this.verificationStatus,
        rejectionReason: clearRejectionReason
            ? null
            : (rejectionReason ?? this.rejectionReason),
      );
}

class UserStore {
  UserStore._();
  static final user = ValueNotifier<UserModel?>(null);
  static final Map<String, _LocalAccount> _accounts = {};

  /// Persisted client registry — feeds the admin "Clients" tab and the
  /// KPI "Total Clients". Entries survive restarts (SharedPreferences).
  static final registeredClients = ValueNotifier<List<UserModel>>([]);

  /// Clears process-local authentication state without touching persistence.
  /// Used by test isolation and by callers that need a fresh in-memory store.
  static void reset() {
    user.value = null;
    _accounts.clear();
    registeredClients.value = [];
    _writeQueue = null;
  }

  // --- Local persistence keys -----------------------------------------
  static const String _kId = 'user_id';
  static const String _kName = 'user_name';
  static const String _kPhone = 'user_phone';
  static const String _kEmail = 'user_email';
  static const String _kRoleIdx = 'user_role_index';
  static const String _kProCode = 'user_pro_code';
  static const String _kProofPath = 'user_proof_path';
  static const String _kSelfiePath = 'user_selfie_path';
  static const String _kVerIdx = 'user_ver_status_index';
  static const String _kVerReason = 'user_ver_reason';
  static const String _kGovernorateAr = 'user_governorate_ar';
  static const String _kGovernorateFr = 'user_governorate_fr';
  // Explicit auto-login keys (written at login/register, wiped at signOut).
  static const String _kIsLoggedIn = 'is_logged_in';
  static const String _kUserRole = 'user_role';

  /// Signed admin-session marker (CodeRabbit): written ONLY by a real admin
  /// sign-in ([setAdminSession]) and re-validated against the LIVE configured
  /// identity in [checkInitialSession] — a raw `user_role:'admin'`
  /// preference without (or with a stale) signature can never route to the
  /// admin shell.
  static const String _kAdminSig = 'admin_session_sig';

  /// Canonical persisted role string: 'client' or 'professionnel'.
  static String _roleKey(UserRole role) =>
      role == UserRole.professional ? 'professionnel' : 'client';

  /// Normalized credential-registry key for [email] (trimmed, lower-case).
  static String _accountKey(String email) => email.trim().toLowerCase();

  /// PASSWORD KDF digest (CodeRabbit): the plaintext password is never
  /// stored, and a SINGLE-PASS hash is too cheap against offline brute-force.
  /// The digest is derived with PBKDF2-HMAC-SHA256 ([pbkdf2Hex]) over a
  /// domain-separated salt built from the registry key (the normalized e-mail
  /// — stable per identity, unknown to anyone who does not already own the
  /// account). Only the HEX DIGEST is persisted and compared.
  static String _hashCredential(String password, String salt) =>
      pbkdf2Hex(password, 'allo-service-pro/credential/v1|$salt');

  /// LEGACY single-pass digest of the PREVIOUS hash rule. Kept ONLY for the
  /// transparent upgrade path in [signIn]/[matchesPassword]: an account
  /// hashed by the old build is authenticated once, then re-stored with the
  /// KDF digest — no user is ever locked out by the upgrade (CodeRabbit).
  static String _legacyHashCredential(String password, String salt) =>
      sha256Hex('allo-service-pro/credential/v1|$salt|$password');

  /// True when [value] is already a SHA-256 hex digest (64 lowercase hex
  /// chars) — i.e. a record written by the CURRENT hash rule. Anything else
  /// is a LEGACY plaintext credential needing migration (CodeRabbit).
  static bool _isDigest(String value) =>
      value.length == 64 && RegExp(r'^[0-9a-f]{64}$').hasMatch(value);

  /// Returns the stored credential, UPGRADED to the salted digest when it is
  /// a legacy plaintext secret (CodeRabbit). Digests pass through unchanged.
  static String _migrateLegacyCredential(String stored, String salt) =>
      _isDigest(stored) ? stored : _hashCredential(stored, salt);

  /// Whether a registry KEY is a legacy phone-keyed entry — i.e. it is not a
  /// valid e-mail address, so the record predates the Email-OTP migration.
  /// ONLY such entries may be reached by the phone-fallback sync.
  static bool _isLegacyPhoneKey(String key) => !AppValidators.isValidEmail(key);

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
  /// The persisted role key is authoritative for the client/professional
  /// routes. The ADMIN route is different (CodeRabbit): an unsigned raw
  /// preference must never grant admin routing, so the persisted marker is
  /// re-validated against the signature derived from the LIVE configured
  /// admin identity — a forged `user_role:'admin'` flag written outside a
  /// real admin sign-in carries no (or a stale) signature and is ignored.
  ///
  /// Returns the route key — 'admin' | 'professionnel' | 'client' — or null
  /// when the device has no active session (guest / signed out).
  static Future<String?> checkInitialSession() async {
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool(_kIsLoggedIn) ?? false)) return null;
    final roleKey = prefs.getString(_kUserRole);
    if (roleKey != null && roleKey.isNotEmpty) {
      if (roleKey == 'admin') {
        // SIGNATURE GATE (CodeRabbit): the marker must match the CURRENTLY
        // configured identity exactly. An unconfigured (closed) gate has no
        // signature at all — every persisted admin flag is unsigned by
        // definition and falls through to the legacy derivation below
        // (which cannot return 'admin').
        final expected = AdminAuth.sessionSignature;
        final stored = prefs.getString(_kAdminSig);
        if (expected == null || stored == null || stored != expected) {
          return null;
        }
      }
      return roleKey;
    }
    // Legacy sessions saved before the role key existed: derive the route
    // from the in-memory session hydrated at startup.
    final u = user.value;
    if (u == null || u.role == null) return null;
    return _roleKey(u.role!);
  }

  static Future<void> set({
    required String name,
    required String phone,
    String? email,
    bool clearEmail = false,
    String? id,
    UserRole? role,
    String? proCode,
    String? governorateAr,
    String? governorateFr,
    String? proofPath,
    String? selfiePath,
    ProVerification? verificationStatus,
    String? rejectionReason,
    // Explicit-clear flags: `set()` merges proCode / proof / selfie /
    // rejectionReason from the previous session when the arg is omitted
    // (null == "not passed"). A sign-in that binds a client account (no PRO
    // code, no rejection) must be able to STRIP another account's values
    // instead of inheriting them — pass the corresponding flag as true.
    bool clearProCode = false,
    bool clearProofPath = false,
    bool clearSelfiePath = false,
    bool clearRejectionReason = false,
  }) async {
    user.value = UserModel(
      id: id ?? 'user_${DateTime.now().microsecondsSinceEpoch}',
      name: name,
      phone: phone,
      // IMMUTABLE by default: an omitted (or blank) [email] PRESERVES the
      // e-mail already bound to the session. The e-mail is the Email-OTP
      // identity AND the credential-registry key, so a session rebuild — a
      // pro re-submitting the registration wizard, a profile refresh, a role
      // switch — must never be able to drop it. Only an explicit
      // `clearEmail: true` removes it.
      email: clearEmail ? null : (_cleanEmail(email) ?? user.value?.email),
      role: role,
      proCode: clearProCode ? null : (proCode ?? user.value?.proCode),
      // Explicit semantics: passing null CLEARS the governorate (the old
      // `?? user.value?...` merge made "all governorates" unselectable).
      // Blank strings are normalized to null as well so no empty entry can
      // ever reach the model and render blank labels in the UI.
      governorateAr: _cleanGov(governorateAr),
      governorateFr: _cleanGov(governorateFr),
      proofPath: clearProofPath ? null : (proofPath ?? user.value?.proofPath),
      selfiePath:
          clearSelfiePath ? null : (selfiePath ?? user.value?.selfiePath),
      verificationStatus: verificationStatus ??
          user.value?.verificationStatus ??
          ProVerification.none,
      rejectionReason: clearRejectionReason
          ? null
          : (rejectionReason ?? user.value?.rejectionReason),
    );
    await persistToPrefs();
    _syncAntiAbuseBinding();
  }

  /// Binds (or clears) the silent anti-abuse counter to this session.
  /// Professionals never own a cancellation tally — only clients do.
  static void _syncAntiAbuseBinding() {
    final u = user.value;
    if (u == null || u.isProfessional) {
      AntiAbuseStore.clearActiveClient();
      return;
    }
    AntiAbuseStore.bindSession(id: u.id, email: u.email);
  }

  // --- Governorate sanitization -----------------------------------------
  /// Treats null / empty / whitespace-only governorate values as null so a
  /// blank selection can never be stored or rendered.
  static String? _cleanGov(String? raw) {
    if (raw == null) return null;
    final v = raw.trim();
    return v.isEmpty ? null : v;
  }

  /// Normalizes an optional e-mail into the CANONICAL session form:
  /// null / blank → null, otherwise trimmed AND lower-cased.
  ///
  /// The registry key IS the lower-cased e-mail ([_accountKey]), so every
  /// e-mail bound to the session must be byte-identical to it — identity
  /// comparisons ([signIn] same-identity check, credential lookups) compare
  /// both sides directly. Keeping "original casing" here made a session
  /// restored from legacy storage (`A@Mail.com`) fail to match its own
  /// `a@mail.com` record.
  static String? _cleanEmail(String? raw) {
    if (raw == null) return null;
    final v = raw.trim().toLowerCase();
    return v.isEmpty ? null : v;
  }

  /// Removes [key] and returns whether storage confirmed it: `false` (or a
  /// platform throw, also `false`) means the stale key may still sit in
  /// SharedPreferences, so the caller MUST treat its cleanup as failed.
  /// Every cleanup call site goes through this helper so a stale key is
  /// always TRACKED (logged) AND propagated — never silently dropped.
  static Future<bool> _removeKey(SharedPreferences prefs, String key) async {
    try {
      final removed = await prefs.remove(key);
      if (!removed) {
        debugPrint('UserStore: failed to remove key "$key" from storage');
      }
      return removed;
    } catch (e) {
      debugPrint('UserStore: failed to remove key "$key" from storage: $e');
      return false;
    }
  }

  /// Writes a prefs string only when meaningful; otherwise strips the key so
  /// stale blank entries are removed instead of lingering as empty strings.
  /// Returns the storage outcome so cleanup callers can propagate it.
  static Future<bool> _writeOrRemove(
    SharedPreferences prefs,
    String key,
    String? value,
  ) async {
    final v = _cleanGov(value);
    if (v == null) {
      return _removeKey(prefs, key);
    }
    try {
      return await prefs.setString(key, v);
    } catch (e) {
      debugPrint('UserStore: failed to write key "$key" to storage: $e');
      return false;
    }
  }

  // --- Local persistence ----------------------------------------------
  /// Global write queue: EVERY SharedPreferences write this store makes
  /// (session snapshot, credential registry, client registry) is appended
  /// to ONE chain and executes strictly one at a time, in call order — so
  /// two overlapping writers can never interleave their writes and a slow
  /// older snapshot can never overwrite a fresher one.
  static Future<void>? _writeQueue;

  static Future<void> _enqueueWrite(Future<void> Function() task) {
    final run = (_writeQueue ?? Future<void>.value()).then((_) => task());
    // Keep the chain alive after a failure — the NEXT write must still run
    // (each task handles its own errors internally).
    _writeQueue = run.then((_) {}, onError: (_) {});
    return run;
  }

  /// Drains the pending write chain so a READ (session / registry restore)
  /// can never observe a STALE snapshot while a just-issued write is still
  /// in flight.
  ///
  /// ORDERING GUARD (CodeRabbit): every write is fire-and-forget through
  /// [_enqueueWrite], so a restore issued right after a registration could
  /// otherwise read the PREVIOUS snapshot (`user_accounts_json: '[]'`),
  /// clear the freshly built in-memory credential registry and make the
  /// immediately following sign-in fail (the just-registered PRO code would
  /// be lost). Waiting for the tail future guarantees the read happens
  /// strictly after every write scheduled before it.
  static Future<void> _awaitPendingWrites() async {
    final pending = _writeQueue;
    if (pending == null) return;
    // The chain itself never throws (failures are absorbed per task), but a
    // defensive catch keeps a restore from ever being blocked by storage.
    try {
      await pending;
    } catch (e) {
      debugPrint('UserStore: pending write flush failed: $e');
    }
  }

  static Future<void> persistToPrefs() => _enqueueWrite(_persistToPrefsNow);

  static Future<void> _persistToPrefsNow() async {
    try {
      final u = user.value;
      final prefs = await SharedPreferences.getInstance();
      if (u == null) return;

      await prefs.setString(_kId, u.id);
      await prefs.setString(_kName, u.name);
      await prefs.setString(_kPhone, u.phone);
      // Null OR blank → the key is stripped (never an empty string) so a
      // cleared e-mail cannot linger in storage and be restored later.
      await _writeOrRemove(prefs, _kEmail, u.email);
      if (u.role != null) await prefs.setInt(_kRoleIdx, u.role!.index);
      // Null proCode actively STRIPS the key (never silently keeps a stale
      // PRO-XXXXX): a client sign-in that cleared proCode in-memory can never
      // resurrect another account's code after a restart.
      if (u.proCode != null) {
        await prefs.setString(_kProCode, u.proCode!);
      } else {
        await _removeKey(prefs, _kProCode);
      }
      // Null OR blank → the key is stripped entirely (never an empty
      // string) so stale blank entries cannot survive a profile update.
      await _writeOrRemove(prefs, _kGovernorateAr, u.governorateAr);
      await _writeOrRemove(prefs, _kGovernorateFr, u.governorateFr);
      // Null proof/selfie actively STRIPS the key (never silently keeps a
      // stale value): persist only writes when non-null, removes otherwise —
      // so a sign-in that cleared these in-memory can never resurrect them.
      if (u.proofPath != null) {
        await prefs.setString(_kProofPath, u.proofPath!);
      } else {
        await _removeKey(prefs, _kProofPath);
      }
      if (u.selfiePath != null) {
        await prefs.setString(_kSelfiePath, u.selfiePath!);
      } else {
        await _removeKey(prefs, _kSelfiePath);
      }
      await prefs.setInt(_kVerIdx, u.verificationStatus.index);
      // Null reason actively STRIPS the key (never silently keeps a stale
      // rejection): a fresh sign-in / resubmission that cleared the reason
      // in-memory can never resurrect another account's rejection text.
      if (u.rejectionReason != null) {
        await prefs.setString(_kVerReason, u.rejectionReason!);
      } else {
        await _removeKey(prefs, _kVerReason);
      }
      // Auto-login markers: the session survives restarts and the role
      // drives the direct routing (client → ClientShell, professionnel →
      // ProShell) performed by the splash screen.
      await prefs.setBool(_kIsLoggedIn, true);
      if (u.role != null) {
        await prefs.setString(_kUserRole, _roleKey(u.role!));
      }
    } catch (e) {
      debugPrint('UserStore.persistToPrefs failed: $e');
      // Best-effort persistence.
    }
  }

  static Future<void> loadFromPrefs() async {
    // ORDERING GUARD (CodeRabbit): drain every write scheduled BEFORE this
    // restore. Without it a registration that happened microseconds ago
    // (its `_persistAccounts()` still in flight) would be read back from the
    // PREVIOUS snapshot — the empty registry would then clobber the fresh
    // in-memory records and the immediately following sign-in would fail.
    await _awaitPendingWrites();
    try {
      final prefs = await SharedPreferences.getInstance();
      // Restore the credential registry FIRST — it must load even when no
      // session is active (fresh restart before any email/password login).
      final rawAccounts = prefs.getString(_kAccounts);
      if (rawAccounts != null) {
        var migratedLegacyCredentials = false;
        final decoded = jsonDecode(rawAccounts) as List;
        _accounts.clear();
        for (final e in decoded) {
          final m = e as Map<String, dynamic>;
          final emailKey = ((m['email'] as String?) ?? '').trim().toLowerCase();
          if (emailKey.isEmpty) continue;
          final verIdx = (m['verIdx'] as int?) ?? ProVerification.none.index;
          final storedPassword = (m['password'] as String?) ?? '';
          final migratedPassword =
              _migrateLegacyCredential(storedPassword, emailKey);
          if (migratedPassword != storedPassword) {
            migratedLegacyCredentials = true;
          }
          _accounts[emailKey] = _LocalAccount(
            name: (m['name'] as String?) ?? '',
            phone: (m['phone'] as String?) ?? '',
            // LEGACY PLAINTEXT MIGRATION ON LOAD (CodeRabbit): a record
            // written by a pre-hash build carries the RAW secret — it is
            // upgraded to the salted digest IMMEDIATELY at restore time so
            // the registry on disk never keeps plaintext longer than one
            // load, and no existing account is ever locked out by upgrade.
            password: migratedPassword,
            role: _roleFromKey(m['role'] as String?),
            proCode: m['proCode'] as String?,
            verificationStatus: ProVerification
                .values[verIdx.clamp(0, ProVerification.values.length - 1)],
            // Migration rule: registrations ALWAYS persist this flag, so a
            // MISSING value can only mean a record written by a pre-OTP-gate
            // build — those are grandfathered (no lock-out on upgrade). A
            // fresh registration is written with `false` and stays locked.
            isVerified: (m['isVerified'] as bool?) ?? true,
            proofPath: m['proofPath'] as String?,
            selfiePath: m['selfiePath'] as String?,
            rejectionReason: m['rejectionReason'] as String?,
          );
        }
        if (migratedLegacyCredentials) {
          // PERSIST THE MIGRATION (CodeRabbit): the on-disk registry is
          // rewritten with the digests right away — a legacy plaintext
          // secret does not survive the upgrade one second longer than the
          // restore itself.
          await _persistAccounts();
        }
      }
    } catch (e) {
      debugPrint('UserStore.loadFromPrefs registry restore failed: $e');
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
        email: _cleanEmail(prefs.getString(_kEmail)),
        role: role,
        proCode: prefs.getString(_kProCode),
        governorateAr: governorateAr,
        governorateFr: governorateFr,
        proofPath: prefs.getString(_kProofPath),
        selfiePath: prefs.getString(_kSelfiePath),
        verificationStatus: ProVerification
            .values[verIdx.clamp(0, ProVerification.values.length - 1)],
        rejectionReason: prefs.getString(_kVerReason),
      );
      _syncAntiAbuseBinding();
    } catch (e) {
      debugPrint('UserStore.loadFromPrefs session restore failed: $e');
      // Corrupted session: fall back to guest state.
    }
  }

  /// Registers a new credential record keyed by the (normalized) EMAIL
  /// address — the app's authentication identity.
  ///
  /// [phone] is OPTIONAL now: the auth flow is email-first (Email OTP),
  /// a phone is only kept when the user provides one (pro contact info
  /// entered later at pro registration).
  static bool register({
    required String name,
    required String email,
    required String password,
    String? phone,
  }) {
    final key = _accountKey(email);
    // Defense-in-depth: the form already validates the format, but no
    // malformed address may ever become a credential key.
    if (!AppValidators.isValidEmail(key) || _accounts.containsKey(key)) {
      return false;
    }
    // Defense-in-depth: normalize the OPTIONAL phone as well so any caller
    // path persists a canonical 8-digit number (or an empty string when
    // the user registers with email only).
    final normalizedPhone = (phone == null || phone.trim().isEmpty)
        ? ''
        : AppValidators.normalizePhone(phone);
    // Credentials start LOCKED (`isVerified: false`): the 6-digit OTP must be
    // validated and consumed (see [markEmailVerified]) before this account can
    // ever be signed into. The flag is persisted explicitly — that is what
    // makes the "missing flag ⇒ grandfathered legacy" migration rule safe.
    //
    // SECURITY (CodeRabbit): ONLY the one-way digest is stored — the
    // plaintext never reaches the credential registry on disk.
    final account = _LocalAccount(
      name: name,
      phone: normalizedPhone,
      password: _hashCredential(password, key),
      isVerified: false,
    );
    _accounts[key] = account;
    _persistAccounts();
    set(name: name, phone: normalizedPhone, email: key);
    _registerClient(name: name, phone: normalizedPhone, email: key);
    return true;
  }

  // ─── E-mail (OTP) verification gate ───────────────────────────────────

  /// Whether the credential record of [email] completed OTP verification.
  static bool isEmailVerified(String email) =>
      _accounts[_accountKey(email)]?.isVerified ?? false;

  /// Whether a credential record exists but is still waiting for the OTP —
  /// the login screen uses this to show a targeted "verify your e-mail"
  /// message instead of a generic "wrong password".
  static bool isAccountAwaitingVerification(String email) {
    final account = _accounts[_accountKey(email)];
    return account != null && !account.isVerified;
  }

  /// Unlocks the credential record of [email] (or of the current session when
  /// [email] is omitted): sets `isVerified = true` and persists it.
  ///
  /// MUST only be called after [EmailOtpService.verifyOtp] returned true — i.e.
  /// once the token has been validated AND consumed. Returns false when no
  /// matching record exists.
  static bool markEmailVerified({String? email}) {
    final key = _accountKey(email ?? user.value?.email ?? '');
    final account = _accounts[key];
    if (account == null || account.isVerified) return account != null;
    _accounts[key] = account.copyWith(isVerified: true);
    _persistAccounts();
    return true;
  }

  /// Whether a persisted credential record exists for [email].
  ///
  /// Used by the OTP screen to distinguish a genuine unlock failure
  /// (record present but could not be released — corrupted storage,
  /// inconsistent state) from a benign absence of record (fresh
  /// registration flows where the account is created after the OTP
  /// handshake completes). Absence of record is NOT a security
  /// failure: the OTP token itself was already validated & consumed.
  static bool hasCredentialRecord({String? email}) {
    final key = _accountKey(email ?? user.value?.email ?? '');
    return _accounts.containsKey(key);
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

  /// Persisted client registry write — serialized through the global write
  /// queue (see [_enqueueWrite]).
  static Future<void> _persistClients() => _enqueueWrite(_persistClientsNow);

  static Future<void> _persistClientsNow() async {
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

  /// True when [password] matches the stored credential for [email].
  ///
  /// Deliberately DIFFERENT from [signIn]: it neither opens a session nor
  /// applies the OTP gate (an unverified record answers `true` here, while
  /// [signIn] refuses it). Its only purpose is to prove that the caller owns an
  /// ABANDONED registration before its OTP handshake is resumed — without this
  /// proof, anyone could claim an unverified e-mail and, in demo mode, read the
  /// freshly issued code straight off the screen.
  static bool matchesPassword({
    required String email,
    required String password,
  }) {
    final key = _accountKey(email);
    final account = _accounts[key];
    if (account == null) return false;
    // KDF COMPARISON (CodeRabbit) — the current PBKDF2 digest rule.
    if (account.password == _hashCredential(password, key)) return true;
    // LEGACY rules (transparent upgrade at the next [signIn]): the previous
    // build's single-pass digest, or a raw plaintext record. This is a pure
    // CHECK — the on-disk upgrade to the KDF digest happens exclusively in
    // [signIn], which is the awaited flow.
    final stored = account.password;
    return stored == _legacyHashCredential(password, key) ||
        (!_isDigest(stored) && stored == password);
  }

  /// Binds (or creates) the local identity for a REMOTE-authenticated user
  /// (Supabase Email-OTP migration).
  ///
  /// The remote provider has ALREADY verified the e-mail address before this
  /// runs — the second factor was completed server-side — so the local record
  /// is created UNLOCKED (`isVerified: true`): re-demanding the local demo OTP
  /// for an identity Supabase just verified would be nonsense. An EXISTING
  /// record keeps its role / PRO code / verification dossier and is force-
  /// unlocked so a Supabase-side verification always counts locally.
  ///
  /// Full session binding then goes through [signIn] — its boundary wipe,
  /// same-identity dossier restoration and persistence guarantees apply
  /// unchanged. Returns `false` when no session could be bound (invalid
  /// address, storage failure) — the caller must block navigation on it.
  static Future<bool> bindRemoteIdentity({
    required String email,
    String? fullName,
  }) async {
    final key = _accountKey(email);
    if (!AppValidators.isValidEmail(key)) return false;
    final existing = _accounts[key];
    if (existing != null) {
      if (!existing.isVerified) {
        _accounts[key] = existing.copyWith(isVerified: true);
        await _persistAccounts();
      }
    } else {
      // Brand-new remote identity: derive a display name from the verified
      // e-mail when none was provided (the user can rename it in-profile).
      final name = (fullName?.trim().isNotEmpty ?? false)
          ? fullName!.trim()
          : key.split('@').first;
      _accounts[key] = _LocalAccount(
        name: name,
        phone: '',
        // Stored as the ONE-WAY digest like every other credential (CodeRabbit):
        // the remote identity carries no local secret, so the digest of the
        // EMPTY credential is persisted — never a raw (even empty) plaintext.
        password: _hashCredential('', key),
        isVerified: true,
      );
      await _persistAccounts();
    }
    // The record's stored DIGEST is re-presented to [signIn] through the
    // `credentialIsDigest` seam: this call path just wrote/read the record
    // itself (the remote provider already proved the e-mail ownership), so
    // the stored digest IS the presented credential — hashing it a second
    // time would never match. The plaintext is never needed anywhere.
    final storedDigest = _accounts[key]!.password;
    return signIn(
      email: key,
      password: storedDigest,
      credentialIsDigest: true,
    );
  }

  static Future<bool> signIn({
    required String email,
    required String password,

    /// INTERNAL SEAM (bindRemoteIdentity only): [password] already IS the
    /// stored hex digest and is compared as-is. Every other caller presents a
    /// plaintext, which is hashed with the account salt here — the registry
    /// never stores (nor ever compares) plaintext.
    bool credentialIsDigest = false,
  }) async {
    final key = _accountKey(email);
    final account = _accounts[key];
    if (account == null) return false;
    // HASHED COMPARISON (CodeRabbit): the presented credential is digested
    // with the SAME salt (the account key) and compared against the stored
    // digest — the plaintext is never held anywhere.
    final presented =
        credentialIsDigest ? password : _hashCredential(password, key);
    if (account.password != presented) {
      // LEGACY CREDENTIAL MIGRATION (CodeRabbit): two pre-KDF formats may
      // still sit in the registry — the RAW plaintext of the very first
      // builds, and the single-pass SHA-256 digest of the previous rule.
      // Both are authenticated transparently and upgraded IN PLACE to the
      // KDF digest, so an app update never locks an existing user out.
      final stored = account.password;
      final isLegacyPlaintext =
          !credentialIsDigest && !_isDigest(stored) && stored == password;
      final isLegacyDigest =
          !credentialIsDigest && stored == _legacyHashCredential(password, key);
      if (!isLegacyPlaintext && !isLegacyDigest) return false;
      _accounts[key] = account.copyWith(password: presented);
      await _persistAccounts();
    }
    // OTP gate (security invariant): an account whose e-mail was never
    // verified keeps its credentials LOCKED — a correct password alone is not
    // enough to open it. The record is unlocked by [markEmailVerified] once the
    // 6-digit token has been validated and consumed.
    if (!account.isVerified) return false;
    // STEP 1 — snapshot the previous session AND the persisted verification
    // data, then run the storage cleanup FIRST — fully awaited and
    // FAILURE-SAFE, before any session mutation below.
    //
    // Every SharedPreferences access is wrapped in try-catch: a storage
    // failure (disk full, plugin error, platform exception) is logged and
    // swallowed so it can NEVER throw past this point and leave the session
    // in a half-mutated / desynced state. Only after the cleanup outcome is
    // known (success OR handled failure) does the code touch `user.value`.
    final previous = user.value;
    String? storedEmail;
    String? storedProCode;
    String? storedProof;
    String? storedSelfie;
    String? storedReason;
    String? storedGovernorateAr;
    String? storedGovernorateFr;
    bool boundaryClean = false;
    // Accumulates EVERY per-key removal outcome: `&` (not `&&`) is
    // deliberate — a failed removal must never short-circuit the remaining
    // removals, yet its `false` must still reach the abort guard below.
    var keysClean = true;
    try {
      // Queued through the global write chain: the snapshot read + boundary
      // removals are strictly ordered AFTER any pending background write,
      // so a late persistToPrefs can never resurrect a removed key.
      await _enqueueWrite(() async {
        final prefs = await SharedPreferences.getInstance();
        // Read BEFORE the removals — these are the previous session's
        // values and the fallback source when preserving verification
        // data below. NOTE: governorate keys are NOT removed here (they
        // are bound by the new session in STEP 2) — they are captured so
        // the SAME-identity session can re-hydrate them without the
        // in-memory boundary wipe losing them.
        storedEmail = prefs.getString(_kEmail);
        storedProCode = prefs.getString(_kProCode);
        storedProof = prefs.getString(_kProofPath);
        storedSelfie = prefs.getString(_kSelfiePath);
        storedReason = prefs.getString(_kVerReason);
        storedGovernorateAr = prefs.getString(_kGovernorateAr);
        storedGovernorateFr = prefs.getString(_kGovernorateFr);
        keysClean = (await _removeKey(prefs, _kProofPath)) & keysClean;
        keysClean = (await _removeKey(prefs, _kSelfiePath)) & keysClean;
        keysClean = (await _removeKey(prefs, _kProCode)) & keysClean;
        keysClean = (await _removeKey(prefs, _kVerReason)) & keysClean;
      });
      // The storage outcome propagates STRICTLY: any single failed removal
      // (or a throw above) keeps the abort guard armed.
      boundaryClean = keysClean;
    } catch (e) {
      debugPrint('UserStore.signIn: boundary key cleanup failed: $e');
    }
    if (!boundaryClean) {
      // ABORT the authentication transition (CodeRabbit): the storage
      // cleanup failed, so the previous account's keys may still sit in
      // SharedPreferences and the fresh session could desync (e.g. inherit
      // a foreign PRO code after a restart). Binding `set()` is strictly
      // skipped — NO session is opened and `user.value` is never mutated.
      // `false` keeps the existing bool contract: the login screen reports
      // a failed sign-in and the user retries once storage recovers.
      return false;
    }
    // VERIFICATION DATA PRESERVATION (CodeRabbit): a pending/rejected
    // professional signing back in must KEEP their submitted proof / selfie
    // and the admin's rejection reason — the gate screen would otherwise
    // render a reasonless "rejected" state and re-submission would be
    // impossible.
    //
    // EXACT-SNAPSHOT MATCHING (CodeRabbit): the dossier is taken STRICTLY
    // and EXCLUSIVELY from the FIRST identity-verified source — its three
    // fields are NEVER mixed across snapshots, so a stale value from one
    // source can never cross-contaminate a fresher one:
    //   1. the live in-memory session (matched by e-mail / PRO code);
    //   2. the persisted session snapshot (matched the same way);
    //   3. the credential registry record (keyed BY the signing-in e-mail,
    //      inherently the exact identity).
    // Whenever NO exact source matches, the hard wipe still applies and
    // nothing ever crosses identities.
    // BOTH sides are normalized: `key` comes from [_accountKey]
    // (trim + lower-case), so the session e-mails are normalized the same
    // way — a legacy/case-variant stored value (`A@Mail.com`) still matches
    // its canonical record (`a@mail.com`).
    final liveMatches = previous != null &&
        (previous.email?.trim().toLowerCase() == key ||
            (account.proCode != null && previous.proCode == account.proCode));
    final storedMatches = storedEmail?.trim().toLowerCase() == key ||
        (account.proCode != null && account.proCode == storedProCode);
    final restoreVerification = account.role == UserRole.professional &&
        (account.verificationStatus == ProVerification.pending ||
            account.verificationStatus == ProVerification.rejected);
    String? restoredProof;
    String? restoredSelfie;
    String? restoredReason;
    if (restoreVerification) {
      // SMART DOSSIER COALESCING (CodeRabbit): per-field fallback across
      // the identity-verified sources, first NON-NULL wins in priority
      // order (registry record → live session → persisted snapshot). An
      // incomplete higher-priority snapshot (one field null — e.g. a
      // resubmission that kept the proof but cleared the reason) must NOT
      // wipe the valid value a lower-priority snapshot still holds.
      //
      // Each source may contribute ONLY when it matched this exact
      // identity (the registry record IS this exact identity — it is keyed
      // by the signing-in e-mail), so per-field coalescing can never
      // cross-contaminate identities: the strict-source guarantee "no
      // unmatched source ever contributes" is fully preserved.
      final liveProof = liveMatches ? previous.proofPath : null;
      final liveSelfie = liveMatches ? previous.selfiePath : null;
      final liveReason = liveMatches ? previous.rejectionReason : null;
      final snapProof = storedMatches ? storedProof : null;
      final snapSelfie = storedMatches ? storedSelfie : null;
      final snapReason = storedMatches ? storedReason : null;
      // CREDENTIAL-RECORD AUTHORITY (CodeRabbit): the persistent registry
      // record is STRICTLY authoritative for current-format dossier fields
      // — it is evaluated FIRST and takes precedence over any (possibly
      // stale) session snapshot. The record mirrors every admin action
      // (reject reason, re-upload, approval) synchronously, so it is the
      // freshest truth. Per-field coalescing keeps the completeness
      // guarantee: a field the record does not carry yet (a pre-dossier-
      // format record) is filled from the freshest identity-verified
      // session snapshot instead of being wiped to null.
      restoredProof = account.proofPath ?? liveProof ?? snapProof;
      restoredSelfie = account.selfiePath ?? liveSelfie ?? snapSelfie;
      restoredReason = account.rejectionReason ?? liveReason ?? snapReason;
    }
    // STEP 1b — in-memory boundary wipe. The clear flags force null (a bare
    // `copyWith(proofPath: null)` would NOT clear — null falls back to the
    // old value via the `?? this.proofPath` merge). Applied strictly AFTER
    // the storage cleanup above, so the session is mutated only once the
    // storage outcome is known and handled. [set()] in STEP 2 re-binds the
    // restored dossier for the same-identity pending/rejected pro.
    if (previous != null &&
        (previous.proofPath != null ||
            previous.selfiePath != null ||
            previous.proCode != null ||
            previous.rejectionReason != null)) {
      user.value = previous.copyWith(
        clearProofPath: true,
        clearSelfiePath: true,
        clearProCode: true,
        clearRejectionReason: true,
      );
    }
    // STEP 2 — bind the clean session. When the incoming account carries its
    // own values they are bound verbatim; when it carries none (client login,
    // fresh session), the explicit clear flags STRIP any residue instead of
    // inheriting the previous account's PRO code / proof / selfie / reason
    // via the `?? user.value?...` merge — no stale artifact from a *previous*
    // account can ever leak into the newly authenticated session. The one
    // exception is [restoreVerification]: a SAME-IDENTITY pending/rejected
    // pro re-binds their own proof, selfie and rejection reason.
    //
    // GOUVERNORATTE PRESERVATION (CodeRabbit): the credential record does
    // NOT carry governorate fields (they live only in the session snapshot).
    // They are restored STRICTLY from the persisted snapshot captured in
    // STEP 1 — but ONLY for the SAME identity (matched by e-mail). A foreign
    // account's governorate can never bleed into this session: the snapshot
    // is only consulted when `storedMatches` is true, and the in-memory
    // boundary wipe in STEP 1b already nulled the previous session's fields
    // so `set()`'s `?? user.value?.governorate…` merge cannot inherit stale
    // data — it falls back to the stored snapshot (or null).
    final restoredGovAr = storedMatches ? storedGovernorateAr : null;
    final restoredGovFr = storedMatches ? storedGovernorateFr : null;
    // AWAITED (CodeRabbit): the session write persists through the global
    // write queue — returning `true` before it settles would let the login
    // screen report a successful sign-in whose persisted state is not yet
    // on disk (a restart right after could restore a half-bound session).
    await set(
      name: account.name,
      phone: account.phone,
      email: key,
      role: account.role,
      proCode: account.proCode,
      clearProCode: account.proCode == null,
      verificationStatus: account.verificationStatus,
      proofPath: restoredProof,
      clearProofPath: restoredProof == null,
      selfiePath: restoredSelfie,
      clearSelfiePath: restoredSelfie == null,
      rejectionReason: restoredReason,
      clearRejectionReason: restoredReason == null,
      // Preserve only the matching identity's governates; strip any residue
      // from a previous account on a fresh sign-in.
      governorateAr: restoredGovAr,
      governorateFr: restoredGovFr,
    );
    // Backfill the registry record so the preserved dossier also survives a
    // sign-out → sign-in cycle and a restart without a live session.
    if (restoreVerification) {
      final record = _accounts[key];
      if (record != null &&
          (record.proofPath != restoredProof ||
              record.selfiePath != restoredSelfie ||
              record.rejectionReason != restoredReason)) {
        _accounts[key] = record.copyWith(
          proofPath: restoredProof,
          clearProofPath: restoredProof == null,
          selfiePath: restoredSelfie,
          clearSelfiePath: restoredSelfie == null,
          rejectionReason: restoredReason,
          clearRejectionReason: restoredReason == null,
        );
        await _persistAccounts();
      }
    }
    return true;
  }

  static Future<void> setRole(UserRole role) async {
    final current = user.value;
    if (current != null) {
      user.value = current.copyWith(role: role);
      // Sync the credential record too, so a later email/password login
      // restores the role instead of re-running the onboarding flow.
      final emailKey = current.email?.trim().toLowerCase();
      final account = (emailKey == null) ? null : _accounts[emailKey];
      if (emailKey != null && account != null) {
        // copyWith preserves `isVerified` — rebuilding a record must never
        // unlock (or re-lock) it as a side effect of picking a role.
        _accounts[emailKey] = account.copyWith(role: role);
        await _persistAccounts();
      }
      // Persist immediately so a restart routes straight to the right shell.
      await persistToPrefs();
    }
    _syncAntiAbuseBinding();
  }

  /// Persists the admin session through the same auto-login flag path used by
  /// client and professional sessions.
  ///
  /// [signature] binds the persisted routing flag to the ACTUAL configured
  /// admin identity (CodeRabbit): [checkInitialSession] re-derives the
  /// expected signature from the live credentials on every cold start and
  /// refuses to route on a missing/stale marker, so a raw
  /// `user_role: 'admin'` preference written outside a real admin sign-in
  /// can never grant the admin shell.
  static Future<void> setAdminSession({String? signature}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kIsLoggedIn, true);
    await prefs.setString(_kUserRole, 'admin');
    if (signature != null) {
      await prefs.setString(_kAdminSig, signature);
    }
  }

  /// Binds the professional identity (PRO-XXXXX + verification state) to the
  /// credential record of the CURRENT session user. Called when a pro submits
  /// the registration form — the record is flushed to SharedPreferences so a
  /// returning pro's email/password login restores the full pro profile.
  ///
  /// AWAITABLE (CodeRabbit): the registry write is enqueued asynchronously —
  /// callers persisting then immediately reloading prefs (tests, cold-restart
  /// simulations) must await this or the record may not be on disk yet.
  static Future<void> bindProAccount({
    required String? proCode,
    required ProVerification verificationStatus,
    String? proofPath,
    String? selfiePath,
  }) async {
    final key = user.value?.email?.trim().toLowerCase();
    if (key == null || !_accounts.containsKey(key)) return;
    _accounts[key] = _accounts[key]!.copyWith(
      role: UserRole.professional,
      proCode: proCode,
      verificationStatus: verificationStatus,
      // Dossier snapshot: the proof/selfie submitted with THIS registration
      // (null keeps whatever the record already carries).
      proofPath: proofPath,
      selfiePath: selfiePath,
    );
    await _persistAccounts();
  }

  /// Admin-side sync — PHONE FALLBACK, LEGACY RECORDS ONLY.
  ///
  /// Reaches a credential record by its (canonical) phone number, which is
  /// meaningful ONLY for pre-Email-OTP entries whose registry key is itself a
  /// phone number. E-mail-keyed records are deliberately EXCLUDED, so a phone
  /// match can never cross-talk with an e-mail account (two different users may
  /// legitimately share a household or office number).
  ///
  /// Use [syncAccountVerificationByEmail] whenever the e-mail is known — it is
  /// the primary path since the e-mail is the authentication identity.
  static Future<void> syncAccountVerificationByPhone(
    String phone, {
    required ProVerification status,
    String? reason,
    bool clearReason = false,
    String? proofPath,
  }) async {
    final target = AppValidators.normalizePhone(phone);
    if (target.isEmpty) return;
    final matches = _accounts.entries
        .where((e) =>
            _isLegacyPhoneKey(e.key) &&
            AppValidators.normalizePhone(e.value.phone) == target)
        .toList();
    if (matches.isEmpty) return;
    for (final e in matches) {
      _accounts[e.key] = e.value.copyWith(
        verificationStatus: status,
        rejectionReason: reason,
        clearRejectionReason: clearReason,
        proofPath: proofPath,
      );
    }
    await _persistAccounts();
  }

  /// Email-identity twin of [syncAccountVerificationByPhone] — the PRIMARY
  /// path since the e-mail is the authentication key (Email OTP). Updates
  /// the credential record keyed by the normalized [email] so a returning
  /// pro's next sign-in restores the current verification state.
  ///
  /// AWAITABLE (CodeRabbit): same contract as [bindProAccount] — the caller
  /// (approvePro / rejectPro / resubmitProof) awaits this so the persisted
  /// registry is settled before anything reloads prefs.
  static Future<void> syncAccountVerificationByEmail(
    String? email, {
    required ProVerification status,
    String? reason,
    bool clearReason = false,
    String? proofPath,
  }) async {
    final key = _accountKey(email ?? '');
    if (key.isEmpty) return;
    final account = _accounts[key];
    if (account == null) return;
    _accounts[key] = account.copyWith(
      verificationStatus: status,
      rejectionReason: reason,
      clearRejectionReason: clearReason,
      proofPath: proofPath,
    );
    await _persistAccounts();
  }

  // --- Credential registry persistence (SharedPreferences) --------------
  static const String _kAccounts = 'user_accounts_json';

  /// Flushes the full credential registry (email · password · role ·
  /// PRO code · OTP verification state) so credentials survive app restarts.
  /// Serialized through the global write queue (see [_enqueueWrite]).
  static Future<void> _persistAccounts() => _enqueueWrite(_persistAccountsNow);

  static Future<void> _persistAccountsNow() async {
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
                // The OTP gate is ALWAYS written explicitly — a record whose
                // flag is missing in storage is therefore a genuine legacy
                // entry (see [loadFromPrefs]), never a brand-new registration.
                'isVerified': e.value.isVerified,
                // Verification dossier: preserved across restarts so a
                // pending/rejected pro can review and re-submit.
                'proofPath': e.value.proofPath,
                'selfiePath': e.value.selfiePath,
                'rejectionReason': e.value.rejectionReason,
              })
          .toList();
      await prefs.setString(_kAccounts, jsonEncode(list));
    } catch (e) {
      debugPrint('UserStore._persistAccounts failed: $e');
      // Storage unavailable — in-memory registry keeps working.
    }
  }

  static Future<void> updateProVerification({
    required ProVerification status,
    String? reason,
    // Explicit-clear flag: a pending resubmission (no reason passed) must
    // STRIP the previous rejection text instead of inheriting it via the
    // `?? this.rejectionReason` merge in [UserModel.copyWith]. Pass
    // `clearReason: true` on resubmit / approve flows.
    bool clearReason = false,
    String? proofPath,
  }) async {
    final current = user.value;
    if (current == null) return;
    user.value = current.copyWith(
      verificationStatus: status,
      rejectionReason: reason,
      clearRejectionReason: clearReason,
      proofPath: proofPath,
    );
    // Mirror into the credential record (CodeRabbit): the proof / selfie /
    // rejection reason must survive a sign-out → sign-in cycle and a
    // restart, so the verification gate can always show WHY and allow a
    // re-submission. The record mirrors the NEW session state exactly.
    final recordKey = current.email?.trim().toLowerCase();
    final next = user.value;
    final record = (recordKey == null) ? null : _accounts[recordKey];
    if (recordKey != null && record != null && next != null) {
      _accounts[recordKey] = record.copyWith(
        verificationStatus: status,
        proofPath: next.proofPath,
        clearProofPath: next.proofPath == null,
        selfiePath: next.selfiePath,
        clearSelfiePath: next.selfiePath == null,
        rejectionReason: next.rejectionReason,
        clearRejectionReason: next.rejectionReason == null,
      );
      await _persistAccounts();
    }
    await persistToPrefs();
  }

  /// Signs the user out and wipes every persisted session key so a restart
  /// lands on the welcome screen instead of silently restoring the session.
  ///
  /// Returns `true` ONLY when the persistent cleanup fully COMPLETED. A
  /// storage failure strictly ABORTS (`false`) without touching the
  /// in-memory session, so no caller can report a successful sign-out that
  /// did not actually happen.
  static Future<bool> signOut() async {
    // ORDERING CONTRACT (CodeRabbit): the IN-MEMORY session wipe is the LAST
    // step, strictly AFTER every persisted cleanup confirmed success. The old
    // order nulled `user.value` first, so an aborted sign-out (a failed key
    // removal below) left a wiped in-memory session on top of a still-live
    // persisted one — the exact desync the abort contract exists to prevent.
    // STEP 1 — boundary cleanup FIRST, awaited, before any session mutation.
    // A failure here is a HARD ABORT: the stale keys may still sit in
    // storage, so wiping the in-memory session now would desync it.
    // `&` (not `&&`) accumulates EVERY per-key outcome without
    // short-circuiting the remaining removals.
    bool boundaryClean = false;
    var boundaryKeysClean = true;
    try {
      // SIGN-OUT SERIALIZATION (CodeRabbit): every removal runs THROUGH the
      // global write queue, strictly ordered after any pending background
      // write — a queued persistToPrefs can never resurrect a session key
      // after it was removed here.
      await _enqueueWrite(() async {
        final prefs = await SharedPreferences.getInstance();
        boundaryKeysClean =
            (await _removeKey(prefs, _kProofPath)) & boundaryKeysClean;
        boundaryKeysClean =
            (await _removeKey(prefs, _kSelfiePath)) & boundaryKeysClean;
        boundaryKeysClean =
            (await _removeKey(prefs, _kProCode)) & boundaryKeysClean;
        boundaryKeysClean =
            (await _removeKey(prefs, _kVerReason)) & boundaryKeysClean;
      });
      // STRICT PROPAGATION (CodeRabbit): any single failed removal keeps the
      // abort guard armed — `true` is assigned ONLY when every key confirmed.
      boundaryClean = boundaryKeysClean;
    } catch (e) {
      debugPrint('UserStore.signOut: boundary key cleanup failed: $e');
    }
    if (!boundaryClean) return false;
    // STEP 2 — full persisted-session wipe. A failure here is also a HARD
    // ABORT: some session keys may remain, so the sign-out did NOT complete.
    // Queued through the same write chain (same ordering guarantee).
    bool sessionClean = false;
    var sessionKeysClean = true;
    try {
      await _enqueueWrite(() async {
        final prefs = await SharedPreferences.getInstance();
        sessionKeysClean =
            (await _removeKey(prefs, _kIsLoggedIn)) & sessionKeysClean;
        sessionKeysClean =
            (await _removeKey(prefs, _kUserRole)) & sessionKeysClean;
        // The signed admin marker must die with the session — a leftover
        // signature paired with a re-forged `user_role:'admin'` flag would
        // survive the logout otherwise.
        sessionKeysClean =
            (await _removeKey(prefs, _kAdminSig)) & sessionKeysClean;
        sessionKeysClean = (await _removeKey(prefs, _kId)) & sessionKeysClean;
        sessionKeysClean = (await _removeKey(prefs, _kName)) & sessionKeysClean;
        sessionKeysClean =
            (await _removeKey(prefs, _kPhone)) & sessionKeysClean;
        sessionKeysClean =
            (await _removeKey(prefs, _kEmail)) & sessionKeysClean;
        sessionKeysClean =
            (await _removeKey(prefs, _kRoleIdx)) & sessionKeysClean;
        sessionKeysClean =
            (await _removeKey(prefs, _kVerIdx)) & sessionKeysClean;
        sessionKeysClean =
            (await _removeKey(prefs, _kGovernorateAr)) & sessionKeysClean;
        sessionKeysClean =
            (await _removeKey(prefs, _kGovernorateFr)) & sessionKeysClean;
      });
      sessionClean = sessionKeysClean;
    } catch (e) {
      debugPrint('UserStore.signOut: session key cleanup failed: $e');
    }
    if (!sessionClean) return false;
    // STEP 3 — IN-MEMORY wipe LAST (only reachable when both storage steps
    // fully succeeded): the session object is dropped and the anti-abuse
    // binding released, so memory and storage agree on "signed out".
    user.value = null;
    AntiAbuseStore.clearActiveClient();
    return true;
  }

  /// Full logout for every role (client / professionnel / admin):
  ///
  /// 1. Wipes the persisted user session — profile, tokens AND the
  ///    auto-login flags (`is_logged_in`, `user_role`) — so a cold app
  ///    restart can NEVER silently restore the previous session.
  /// 2. Resets every session-scoped local store back to its defaults
  ///    (subscription, pro profile, chats, orders, notifications,
  ///    home governorate filter).
  ///
  /// Returns `true` ONLY when the persisted cleanup AND every store reset
  /// completed. Returns `false` when [signOut] aborted on a storage failure:
  /// the session stays ALIVE and NOTHING is reset or navigated away from —
  /// callers MUST check the result and block navigation on `false`.
  static Future<bool> signOutAndReset() async {
    // REMOTE SESSION TEARDOWN (Supabase migration) — STRICTLY FIRST and
    // AWAITED: the device may hold an authenticated Supabase session, and a
    // purely local wipe would be "healed" on the next boot by
    // [onAuthStateChange]'s initialSession event. A GENUINE server refusal
    // (online, remote revocation failed) is an ABORT: `false` is returned
    // BEFORE any local state changes, so a device can never end up believing
    // it signed out while a live remote session remains. Offline and
    // local-only builds report success (nothing to revoke) — see
    // [SupabaseAuthService.signOut].
    final remoteRevoked = await SupabaseAuthService.signOut();
    if (!remoteRevoked) {
      debugPrint('UserStore.signOutAndReset: remote sign-out refused — '
          'local session kept intact (no partial sign-out).');
      return false;
    }
    final fullyCleaned = await signOut();
    if (!fullyCleaned) {
      // STRICT HALT (CodeRabbit): the persisted cleanup failed, so the
      // session stays ALIVE — resetting the scoped stores now would leave a
      // half-signed-out hybrid state. Nothing is reset; the caller can
      // retry the sign-out once storage recovers.
      return false;
    }
    await SubscriptionStore.reset();
    await ProProfileStore.reset();
    // CUSTOMER-SCOPED DATA (CodeRabbit): orders and their chat rooms belong
    // to the signed-in identity, so they are wiped with the session. Keeping
    // them in memory after a logout leaked one customer's order history,
    // addresses and conversations to whoever signs in next on this device.
    // (The marketplace copies stay intact on the backend/registry — this is
    // only the device-side session view being cleared.)
    RequestStore.reset();
    ChatStore.reset();
    NotificationStore.clear();
    GovernorateFilterStore.reset();
    return true;
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
    this.isVerified = false,
    this.proofPath,
    this.selfiePath,
    this.rejectionReason,
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

  /// E-mail (OTP) verification state — the account's ACTIVE flag.
  ///
  /// A freshly registered record starts `false` ("credentials locked") and is
  /// only flipped by [UserStore.markEmailVerified], which runs right after the
  /// 6-digit OTP has been validated AND consumed. [UserStore.signIn] refuses
  /// any record that is still locked, so a leaked/guessed password alone can
  /// never open an unverified account.
  final bool isVerified;

  /// Verification dossier snapshots (CodeRabbit): submitted proof / selfie
  /// and the admin's rejection reason. Persisted with the record so a
  /// pending/rejected pro can ALWAYS see why and re-submit — even after a
  /// sign-out → sign-in cycle or an app restart.
  final String? proofPath;
  final String? selfiePath;
  final String? rejectionReason;

  /// Copy helper — every mutation site must go through it so no field
  /// (role · PRO code · verification state · [isVerified] · dossier) is ever
  /// dropped by accident while rebuilding the record.
  _LocalAccount copyWith({
    String? name,
    String? phone,
    String? password,
    UserRole? role,
    String? proCode,
    ProVerification? verificationStatus,
    bool? isVerified,
    String? proofPath,
    bool clearProofPath = false,
    String? selfiePath,
    bool clearSelfiePath = false,
    String? rejectionReason,
    bool clearRejectionReason = false,
  }) {
    return _LocalAccount(
      name: name ?? this.name,
      phone: phone ?? this.phone,
      password: password ?? this.password,
      role: role ?? this.role,
      proCode: proCode ?? this.proCode,
      verificationStatus: verificationStatus ?? this.verificationStatus,
      isVerified: isVerified ?? this.isVerified,
      proofPath: clearProofPath ? null : (proofPath ?? this.proofPath),
      selfiePath: clearSelfiePath ? null : (selfiePath ?? this.selfiePath),
      rejectionReason: clearRejectionReason
          ? null
          : (rejectionReason ?? this.rejectionReason),
    );
  }
}
