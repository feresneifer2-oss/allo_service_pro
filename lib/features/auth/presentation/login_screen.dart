import 'package:flutter/material.dart';

import 'package:allo_service_pro/features/admin/application/admin_store.dart';
import 'package:allo_service_pro/features/admin/presentation/admin_dashboard_screen.dart';
import 'package:allo_service_pro/shared/localization/app_localizations.dart';
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

  void _login() {
    final email = _emailCtrl.text.trim();
    final pass = _passCtrl.text.trim();

    if (email.isEmpty || pass.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Veuillez remplir tous les champs.')),
      );
      return;
    }

    // Smart admin routing: admin credentials bypass regular authentication
    // and land directly on the admin dashboard.
    if (AdminStore.matchesAdmin(email.toLowerCase(), pass)) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const AdminDashboardScreen()),
        (route) => false,
      );
      return;
    }

    if (!UserStore.signIn(email: email, password: pass)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Adresse e-mail ou mot de passe incorrect.')),
      );
      return;
    }
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LanguageScreen()),
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
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: MediaQuery.of(context).size.height - 120,
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
                            title: const Text('Réinitialiser le mot de passe'),
                            content: Text(
                              email.isEmpty
                                  ? 'Saisissez votre adresse e-mail puis réessayez.'
                                  : 'Le lien de réinitialisation sera envoyé à $email dès la connexion à Firebase.',
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
                          fr: 'Mot de passe oublié ?',
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
                              fr: 'Créer un compte', ar: 'إنشاء حساب')),
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
