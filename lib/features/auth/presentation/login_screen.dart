import 'dart:async';

import 'package:flutter/material.dart';

import 'package:allo_service_pro/core/navigation/client_shell.dart';
import 'package:allo_service_pro/core/navigation/pro_shell.dart';
import 'package:allo_service_pro/features/admin/application/admin_store.dart';
import 'package:allo_service_pro/features/admin/data/admin_auth_repository.dart';
import 'package:allo_service_pro/features/admin/presentation/admin_dashboard_screen.dart';
import 'package:allo_service_pro/shared/localization/app_localizations.dart';
import 'package:allo_service_pro/shared/validators.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../application/supabase_auth_service.dart';
import '../application/user_store.dart';
import '../application/verification_sync_service.dart';
import '../data/profile_repository.dart';
import '../../requests/application/request_store.dart';
import 'language_screen.dart';
import 'otp_screen.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _obscure = true;

  /// Double-tap guard (audit remediation): a second tap while a sign-in /
  /// admin-verification round-trip is in flight must be a no-op.
  bool _busy = false;

  Future<void> _login() async {
    if (_busy) return;
    _busy = true;
    try {
      await _loginInner();
    } finally {
      _busy = false;
    }
  }

  Future<void> _loginInner() async {
    final email = _emailCtrl.text.trim();
    final pass = _passCtrl.text.trim();

    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Veuillez remplir tous les champs.')),
      );
      return;
    }

    // The e-mail is the authentication identity (Email-OTP sign-up): reject a
    // malformed address before it reaches the credential registry.
    if (!AppValidators.isValidEmail(email)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.translate(context,
              fr: 'Adresse e-mail invalide.', ar: 'بريد إلكتروني غير صالح.')),
        ),
      );
      return;
    }

    // ── PHASE 3T + FACEBOOK-STYLE PASSWORD ──
    // A configured client means the e-mail channel is REAL. When a password
    // is typed, it is exchanged for a Supabase session FIRST (registration
    // persisted it via `setPassword` right after the OTP handshake) — only a
    // password failure falls through to the 6-digit code
    // (`shouldCreateUser: false`). The server-side ADMIN gate below stays
    // first: an enrolled operator must never be mistaken for a normal user.
    if (SupabaseAuthService.isConfigured) {
      if (pass.isNotEmpty) {
        // ADMIN ESCAPE HATCH (unchanged, server-first): the operator's real
        // Supabase e-mail/password is exchanged for a session and
        // `public.is_admin()` — keyed on the resulting auth.uid() — is the
        // sole authority. Any failure answers null and falls THROUGH to the
        // OTP dispatch: a normal user who typed a password must still reach
        // the code path, and NO local password check runs while Supabase is
        // configured.
        final adminUid = await AdminAuth.instance.verifyAdminCredentials(
          email: email,
          password: pass,
        );
        if (adminUid != null) {
          // The persisted marker is the SERVER-verified uid: the cold-start
          // route re-runs the same server check before trusting it.
          await UserStore.setAdminSession(adminUid: adminUid);
          if (!mounted) return;
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => const AdminDashboardScreen()),
            (route) => false,
          );
          return;
        }
        if (!mounted) return;
      }
      // ── FACEBOOK-STYLE PASSWORD FIRST (non-admin users) ──
      // A typed password is exchanged for a Supabase session BEFORE any OTP
      // is dispatched: registration persisted it via `setPassword` right
      // after the OTP handshake, so every later sign-in needs email+password
      // only. `_reuseExistingEntry` navigates itself on success; any failure
      // (wrong password, unknown address, offline) falls THROUGH to the OTP
      // dispatch below, which stays the universal fallback.
      if (pass.isNotEmpty &&
          await _reuseExistingEntry(email: email, password: pass)) {
        return;
      }
      await _requestLoginOtp(email);
      return;
    }

    // ── LOCAL / DEBUG FALLBACK (Supabase genuinely unconfigured) ──
    // Preserved verbatim: offline-first demo builds keep signing in against
    // the local credential registry.
    if (pass.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Veuillez remplir tous les champs.')),
      );
      return;
    }

    // signIn is async by design: the boundary wipe (in-memory clear +
    // awaited SharedPreferences key removals) must complete strictly BEFORE
    // the new session is bound and persisted — a fire-and-forget removal
    // could otherwise race persistToPrefs() and wipe the fresh PRO code.
    if (!await UserStore.signIn(email: email, password: pass)) {
      // ADMIN PATH (Phase 1 — SERVER-SIDE AUTHORIZATION): the local
      // credential registry has no record for this identity, so the only
      // remaining way in is an administrator whose membership the BACKEND
      // confirms. The operator's real Supabase e-mail/password is exchanged
      // for a Supabase session (signInWithPassword) and `public.is_admin()`
      // — keyed on the resulting auth.uid() — is the sole authority. Any
      // failure (wrong credentials, not an admin, revoked enrolment,
      // offline, Supabase not configured) answers null and falls through to
      // the generic refusal below. No client-side secret and no client-side
      // credential comparison is involved anywhere in this flow.
      final adminUid = await AdminAuth.instance.verifyAdminCredentials(
        email: email,
        password: pass,
      );
      if (adminUid != null) {
        // The persisted marker is the SERVER-verified uid: the cold-start
        // route re-runs the same server check before trusting it.
        await UserStore.setAdminSession(adminUid: adminUid);
        if (!mounted) return;
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const AdminDashboardScreen()),
          (route) => false,
        );
        return;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Adresse e-mail ou mot de passe incorrect.')),
      );
      return;
    }

    if (!mounted) return;
    // Mirror the persisted admin registry (subscription · tokens · approval)
    // into the live session stores BEFORE routing — zero desync.
    await AdminStore.syncSessionStoresForCurrentUser();
    if (!mounted) return;
    // Role-aware routing (shared helper): a returning pro goes STRAIGHT to
    // ProShell — its internal gates render the pending-approval screen, the
    // suspended (Compte Bloque) screen or the dashboard according to the
    // CURRENT persisted status. A returning client skips onboarding too. Only
    // a legacy account with no stored role replays onboarding.
    final destination = _postLoginDestination();
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => destination),
      (route) => false,
    );
  }

  /// ── "RETURNING IDENTITY: ENTER WITHOUT A NEW CODE" (Phase 3U) ──────────
  ///
  /// Attempts the two SERVER-side proofs that make a second e-mail code
  /// pointless, in order of cost:
  ///   (a) the PERSISTED Supabase session ([persistSession]) still
  ///       authenticates this very address — nothing to ask, nothing to
  ///       exchange;
  ///   (b) otherwise the typed password is exchanged for a session
  ///       (`signInWithPassword`). An empty password is simply skipped.
  ///
  /// On success the remote identity is bound locally ([UserStore.
  /// bindRemoteIdentity]) and the role-aware destination is pushed.
  ///
  /// Returns `true` once the user was routed in, `false` when no proof was
  /// available — the caller then falls back to the OTP dispatch, so this
  /// helper can only ever SHORTEN a legitimate flow.
  Future<bool> _reuseExistingEntry({
    required String email,
    required String password,
  }) async {
    final sessionEmail = _liveSessionEmail();
    var authenticated = sessionEmail != null && sessionEmail == email;
    if (!authenticated && password.isNotEmpty) {
      authenticated =
          await SupabaseAuthService.signInWithPassword(email, password);
    }
    if (!authenticated) return false;
    // A remote proof is not enough: the LOCAL session must bind too (the
    // whole app reads UserStore). A binding failure keeps the user on this
    // screen and falls back to the code path.
    if (!await UserStore.bindRemoteIdentity(email: email)) return false;
    if (!mounted) return false;
    // SERVER ROLE HYDRATION (routing fix): the local binding above only
    // replays THIS device's credential registry — on a fresh install it
    // knows no role yet, so `_postLoginDestination` would replay onboarding
    // (LanguageScreen) even though `public.profiles` holds the authoritative
    // one. Failure-tolerant read of the caller's OWN row (RLS) applied ONLY
    // when a known role answers — null keeps today's behavior and can never
    // block a legitimate sign-in.
    final serverRole = await _readServerRole();
    if (!mounted) return false;
    if (serverRole != null) {
      final current = UserStore.user.value;
      if (current != null) {
        await UserStore.set(
          name: current.name,
          phone: current.phone,
          email: current.email,
          id: current.id,
          role: serverRole,
          // Preserve everything `bindRemoteIdentity` already restored — a
          // pure role override: no clearX flags, every other field is
          // re-presented verbatim from the live session.
          proCode: current.proCode,
          governorateAr: current.governorateAr,
          governorateFr: current.governorateFr,
          proofPath: current.proofPath,
          selfiePath: current.selfiePath,
          verificationStatus: current.verificationStatus,
          rejectionReason: current.rejectionReason,
        );
        if (!mounted) return false;
      }
    }

    // Mirror the persisted registry (subscription · tokens · approval) into
    // the live session stores BEFORE routing — zero desync, exactly like the
    // OTP success path. Runs AFTER the server-role hydration above so
    // `_applyServerVerificationAuthority` sees the hydrated professional
    // role on fresh devices — otherwise it early-returns on !isProfessional
    // and `professionals.is_verified` is never read from Supabase.
    await AdminStore.syncSessionStoresForCurrentUser();
    if (!mounted) return false;

    // Phase 7-5: trigger a verification sync in the background so the
    // fresh session's status is confirmed non-blockingly.
    unawaited(VerificationSyncService.syncNow(force: true));

    // Phase B: re-hydrate orders now that the session is authenticated.
    // Startup hydration (main.dart) ran BEFORE login → RLS returned 0 rows.
    unawaited(RequestStore.hydrateFromSupabase());
    // Phase 4C: hydrate approved pros (client feed).
    unawaited(AdminStore.hydrateApprovedProsFromSupabase());
    FocusScope.of(context).unfocus();
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (_) => _postLoginDestination(explicitRole: serverRole),
      ),
      (route) => false,
    );
    return true;
  }

  /// The NORMALIZED e-mail of the currently authenticated Supabase session,
  /// or `null` when there is none (unconfigured/uninitialized client, signed
  /// out device, storage failure). Never throws into the UI.
  String? _liveSessionEmail() {
    try {
      return Supabase.instance.client.auth.currentSession?.user.email
          ?.trim()
          .toLowerCase();
    } catch (e) {
      debugPrint('LoginScreen: no live Supabase session ($e)');
      return null;
    }
  }

  /// SERVER ROLE HYDRATION — the caller's own `public.profiles.role`, read
  /// after a password sign-in (RLS `profiles_select_own_row` scopes it to
  /// `auth.uid()`).
  ///
  /// `null` on ANY failure (unconfigured client, no live session, missing
  /// row/column, unrecognized value): the caller then keeps the local
  /// behavior — a role-less identity replays onboarding. Never throws into
  /// the UI, never blocks a legitimate sign-in.
  Future<UserRole?> _readServerRole() async {
    for (var attempt = 0; attempt < 3; attempt++) {
      final role = await _tryReadServerRoleOnce();
      if (role != null) return role;
      if (attempt < 2) {
        // AUTH TOKEN PROPAGATION DELAY: signInWithPassword returns before
        // the token is fully propagated to PostgREST. Retry with backoff.
        await Future.delayed(Duration(milliseconds: 300 * (attempt + 1)));
      }
    }
    return null;
  }

  Future<UserRole?> _tryReadServerRoleOnce() async {
    try {
      if (!SupabaseAuthService.isConfigured) return null;
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid == null || uid.isEmpty) return null;
      final row = await ProfileRepository.fetchProfile(uid);
      final raw = row?['role']?.toString().trim().toLowerCase();
      if (raw == 'client') return UserRole.client;
      if (raw == 'professional' || raw == 'professionnel') {
        return UserRole.professional;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Role-aware destination shared by BOTH sign-in paths (Phase 3U): a
  /// returning pro lands on [ProShell] (its internal gates render the
  /// pending-approval / suspended / dashboard state), a returning client on
  /// [ClientShell] (onboarding skipped), and only a role-less identity replays
  /// onboarding through [LanguageScreen].
  /// Navigates based on the EXPLICIT role when provided, otherwise falls
  /// back to UserStore.user.value. The explicit role wins to survive races
  /// with the auth event listener (_bindRemoteUser).
  Widget _postLoginDestination({UserRole? explicitRole}) {
    final u = UserStore.user.value;
    final role = explicitRole ?? u?.role;
    if (role == UserRole.professional) return const ProShell();
    if (role == UserRole.client) return const ClientShell();
    // Legacy fallback: check the model's isProfessional getter too
    if (u != null && u.isProfessional) return const ProShell();
    if (u?.role != null) return const ClientShell();
    return const LanguageScreen();
  }

  /// Dispatches the LOGIN OTP (Phase 3T).
  ///
  /// `shouldCreateUser: false`: signing in must never silently provision a
  /// NEW account — an unknown address is answered with a generic refusal
  /// pointing to the sign-up screen. A 429 (provider rate limit) gets its
  /// own "try again later" message; transport failures keep the connectivity
  /// guidance. Raw provider errors are NEVER shown to the user.
  Future<void> _requestLoginOtp(String email) async {
    final OtpSendOutcome outcome;
    try {
      outcome =
          await SupabaseAuthService.sendOtp(email, shouldCreateUser: false);
    } catch (e) {
      debugPrint('LoginScreen: login OTP dispatch failed on the transport '
          'layer: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.translate(context,
              fr: "Échec d'envoi — vérifiez votre connexion Internet puis réessayez.",
              ar: 'فشل الإرسال — تحقّق من اتصالك بالإنترنت ثم أعد المحاولة.')),
        ),
      );
      return;
    }
    if (!mounted) return;
    final message = switch (outcome) {
      OtpSendOutcome.sent => AppLocalizations.translate(context,
          fr: 'Un code de connexion a été envoyé à votre e-mail.',
          ar: 'تم إرسال رمز الدخول إلى بريدك الإلكتروني.'),
      OtpSendOutcome.rateLimited => AppLocalizations.translate(context,
          fr: 'Trop de tentatives. Réessayez dans quelques minutes.',
          ar: 'محاولات كثيرة. أعد المحاولة بعد بضع دقائق.'),
      OtpSendOutcome.refused => AppLocalizations.translate(context,
          fr: "Impossible d'envoyer un code à cette adresse. Vérifiez l'e-mail ou créez un compte.",
          ar: 'تعذّر إرسال رمز إلى هذا البريد. تحقّق من العنوان أو أنشئ حساباً.'),
    };
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
    if (outcome != OtpSendOutcome.sent) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OtpScreen(email: email, createUserOnSend: false),
      ),
    );
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: MediaQuery.of(context).size.height -
                  MediaQuery.of(context).padding.top -
                  kToolbarHeight -
                  MediaQuery.of(context).padding.bottom,
            ),
            child: IntrinsicHeight(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 20),
                  Text(
                    AppLocalizations.translate(context,
                        fr: 'Connexion', ar: 'تسجيل الدخول'),
                    style: const TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    AppLocalizations.translate(context,
                        fr: 'Content de vous revoir 👋',
                        ar: 'مرحبا بك من جديد 👋'),
                    style: const TextStyle(
                      fontSize: 18,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 40),
                  TextField(
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      hintText: AppLocalizations.translate(context,
                          fr: 'Adresse e-mail', ar: 'البريد الإلكتروني'),
                      prefixIcon: const Icon(Icons.email_outlined),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _passCtrl,
                    obscureText: _obscure,
                    decoration: InputDecoration(
                      hintText: AppLocalizations.translate(context,
                          fr: 'Mot de passe', ar: 'كلمة المرور'),
                      prefixIcon: const Icon(Icons.lock_outline_rounded),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscure
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () {
                        final email = _emailCtrl.text.trim();
                        showDialog<void>(
                          context: context,
                          builder: (dialogContext) => AlertDialog(
                            title: const Text('Reinitialiser le mot de passe'),
                            content: Text(
                              email.isEmpty
                                  ? 'Saisissez votre adresse e-mail puis reessayez.'
                                  : 'Le lien de reinitialisation sera envoye a $email.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(dialogContext),
                                child: const Text('OK'),
                              ),
                            ],
                          ),
                        );
                      },
                      child: Text(AppLocalizations.translate(context,
                          fr: 'Mot de passe oublie ?',
                          ar: 'نسيت كلمة المرور؟')),
                    ),
                  ),
                  const Spacer(),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _login,
                      child: Text(AppLocalizations.translate(context,
                          fr: 'Se connecter', ar: 'تسجيل الدخول')),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Center(
                    child: Column(
                      children: [
                        Text(
                          AppLocalizations.translate(context,
                              fr: "Vous n'avez pas de compte ?",
                              ar: "ليس لديك حساب؟"),
                          style: const TextStyle(color: Colors.grey),
                        ),
                        TextButton(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const RegisterScreen(),
                              ),
                            );
                          },
                          child: Text(AppLocalizations.translate(context,
                              fr: 'Creer un compte', ar: 'إنشاء حساب')),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
