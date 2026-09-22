import 'package:flutter/material.dart';

import 'package:allo_service_pro/core/navigation/client_shell.dart';
import 'package:allo_service_pro/core/navigation/pro_shell.dart';
import 'package:allo_service_pro/features/admin/application/admin_store.dart';
import 'package:allo_service_pro/features/admin/data/admin_auth_repository.dart';
import 'package:allo_service_pro/features/admin/presentation/admin_dashboard_screen.dart';
import 'package:allo_service_pro/shared/localization/app_localizations.dart';
import 'package:allo_service_pro/shared/validators.dart';
import '../application/user_store.dart';
import 'language_screen.dart';
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

  Future<void> _login() async {
    final email = _emailCtrl.text.trim();
    final pass = _passCtrl.text.trim();

    if (email.isEmpty || pass.isEmpty) {
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

    // Smart admin routing — delegated to AdminAuthRepository (async by
    // design: the production implementation is a server-side RPC).
    if (await AdminStore.matchesAdmin(email, pass)) {
      // SIGNED admin session (CodeRabbit): the persisted routing flag is
      // stored together with a signature derived from the configured admin
      // identity — an unsigned raw preference can never restore the admin
      // route on a cold start.
      await UserStore.setAdminSession(
        signature: AdminAuth.sessionSignature,
      );

      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const AdminDashboardScreen()),
        (route) => false,
      );
      return;
    }

    // signIn is async by design: the boundary wipe (in-memory clear +
    // awaited SharedPreferences key removals) must complete strictly BEFORE
    // the new session is bound and persisted — a fire-and-forget removal
    // could otherwise race persistToPrefs() and wipe the fresh PRO code.
    if (!await UserStore.signIn(email: email, password: pass)) {
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
    // Role-aware routing: a returning pro goes STRAIGHT to ProShell - its
    // internal gates render the pending-approval screen, the suspended
    // (Compte Bloque) screen or the dashboard according to the CURRENT
    // persisted status. A returning client skips onboarding too. Only a
    // legacy account with no stored role replays onboarding.
    final u = UserStore.user.value;
    final Widget destination;
    if (u != null && u.isProfessional) {
      destination = const ProShell();
    } else if (u?.role != null) {
      destination = const ClientShell();
    } else {
      destination = const LanguageScreen();
    }
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => destination),
      (route) => false,
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
