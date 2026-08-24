import 'package:flutter/material.dart';
import 'package:allo_service_pro/core/navigation/client_shell.dart';
import 'package:allo_service_pro/core/navigation/pro_shell.dart';
import 'package:allo_service_pro/shared/app_locale.dart';
import 'package:allo_service_pro/features/auth/application/user_store.dart';

class AccountTypeScreen extends StatefulWidget {
  const AccountTypeScreen({super.key});

  @override
  State<AccountTypeScreen> createState() => _AccountTypeScreenState();
}

class _AccountTypeScreenState extends State<AccountTypeScreen> {
  String? selectedType;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xffF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr(
                    context,
                    fr: "Comment utilisez-vous Allo Service ?",
                    ar: "كيفاش تحب تستعمل Allo Service؟",
                  ),
                  style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  tr(
                    context,
                    fr: "Ce choix détermine votre expérience dans l'application.",
                    ar: "الاختيار هذا يحدد تجربتك في التطبيق.",
                  ),
                  style: const TextStyle(
                    fontSize: 17,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 35),
                _buildCard(
                  icon: Icons.person_outline,
                  title: tr(context, fr: "Client", ar: "أنا حريف"),
                  subtitle: tr(
                    context,
                    fr: "Je cherche et réserve des services.",
                    ar: "نحب نلقى ونحجز خدمات.",
                  ),
                  value: "client",
                ),
                const SizedBox(height: 20),
                _buildCard(
                  icon: Icons.work_outline,
                  title: tr(context, fr: "Professionnel", ar: "أنا مهني"),
                  subtitle: tr(
                    context,
                    fr: "Je propose mes services aux clients.",
                    ar: "نحب نقدم خدمات.",
                  ),
                  value: "pro",
                ),
                const SizedBox(height: 40),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: selectedType == null
                        ? null
                        : () {
                            UserStore.setRole(
                              selectedType == 'client'
                                  ? UserRole.client
                                  : UserRole.professional,
                            );
                            if (selectedType == "client") {
                              Navigator.pushReplacement(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => const ClientShell()),
                              );
                            } else {
                              Navigator.pushReplacement(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => const ProShell()),
                              );
                            }
                          },
                    child: Text(
                      tr(context, fr: "Continuer", ar: "متابعة"),
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required String value,
  }) {
    final selected = selectedType == value;

    return GestureDetector(
      onTap: () => setState(() => selectedType = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? const Color(0xff2563EB) : Colors.grey.shade300,
            width: selected ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .05),
              blurRadius: 15,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 65,
              height: 65,
              decoration: BoxDecoration(
                color: selected
                    ? const Color(0xff2563EB)
                    : const Color(0xffEFF6FF),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(
                icon,
                size: 32,
                color: selected ? Colors.white : const Color(0xff2563EB),
              ),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? const Color(0xff2563EB) : Colors.grey,
                  width: 2,
                ),
                color: selected ? const Color(0xff2563EB) : Colors.transparent,
              ),
              child: selected
                  ? const Icon(Icons.check, color: Colors.white, size: 16)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
