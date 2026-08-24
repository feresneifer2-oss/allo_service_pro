import 'package:flutter/material.dart';

import 'package:allo_service_pro/core/theme/app_colors.dart';
import 'package:allo_service_pro/features/auth/application/user_store.dart';
import 'package:allo_service_pro/features/chat/application/chat_store.dart';
import 'package:allo_service_pro/features/chat/models/chat_session.dart';
import 'package:allo_service_pro/features/chat/presentation/chat_screen.dart';
import 'package:allo_service_pro/features/requests/application/request_store.dart';
import 'package:allo_service_pro/features/requests/models/service_request.dart';
import 'package:allo_service_pro/features/support/presentation/support_screen.dart';
import 'package:allo_service_pro/shared/app_locale.dart' show appLocale, tr;

class MessagesListScreen extends StatelessWidget {
  const MessagesListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(tr(context, fr: 'Messages', ar: 'الرسائل')),
      ),
      body: ValueListenableBuilder<List<ServiceRequest>>(
        valueListenable: RequestStore.requests,
        builder: (context, all, _) =>
            ValueListenableBuilder<Map<String, ChatSession>>(
          valueListenable: ChatStore.sessions,
          // Réagit aussi aux changements de sessions : une expiration ou une
          // fermeture admin retire la ligne immédiatement, pas seulement au
          // moment du clic.
          builder: (context, _, __) {
            // Source de vérité unique : la liste reflète exactement ce que
            // RequestStore.isChatAllowed accepte (statut vivant + session
            // active non expirée). Aucune ligne ne peut donc mener à un chat
            // verrouillé (terminé, annulé, expiré ou fermé par l'admin).
            final chats =
                all.where((r) => RequestStore.isChatAllowed(r.id)).toList();

            if (chats.isEmpty) {
              return Center(
                child: Text(
                  tr(context, fr: 'Aucun message', ar: 'لا رسائل'),
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              );
            }

            return ListView.builder(
              padding: const EdgeInsets.all(20),
              itemCount: chats.length,
              itemBuilder: (_, i) {
                final r = chats[i];
                final service =
                    tr(context, fr: r.serviceTitleFr, ar: r.serviceTitleAr);
                return ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  tileColor: Colors.white,
                  leading: CircleAvatar(
                    backgroundColor: AppColors.primarySurface,
                    child: Text(
                        (r.professionalName.trim().isNotEmpty
                            ? r.professionalName.trim()[0]
                            : '?'),
                        style: const TextStyle(color: AppColors.primary)),
                  ),
                  title: Text(r.professionalName,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(service),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
                    // Filet de sécurité : l'état peut changer entre
                    // l'affichage et le tap (expiration à l'instant T,
                    // clôture admin simultanée).
                    if (!RequestStore.isChatAllowed(r.id)) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(tr(context,
                              fr: 'Chat indisponible pour cette demande.',
                              ar: 'المحادثة غير متاحة لهذا الطلب.')),
                        ),
                      );
                      return;
                    }
                    ChatStore.seedDemo(r.id);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => ChatScreen(requestId: r.id)),
                    );
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class CustomerProfileScreen extends StatelessWidget {
  const CustomerProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: UserStore.user,
      builder: (context, user, _) {
        final name = user?.name ?? UserStore.displayName;
        final phone = user?.phone ?? '+216 XX XXX XXX';
        final email =
            user?.email ?? tr(context, fr: 'Non renseigné', ar: 'غير محدد');
        final accountId = (user?.id.trim().isNotEmpty ?? false)
            ? user!.id.trim()
            : '—';
        // Garde-fou : évite un RangeError si le nom est vide ou blanc.
        final avatarInitial =
            (name.trim().isNotEmpty ? name.trim()[0] : '?').toUpperCase();

        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            title: Text(tr(context, fr: 'Profil', ar: 'الملف الشخصي')),
          ),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Center(
                  child: CircleAvatar(
                    radius: 48,
                    backgroundColor: AppColors.primarySurface,
                    child: Text(
                      avatarInitial,
                      style: const TextStyle(
                          fontSize: 36,
                          color: AppColors.primary,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Center(
                  child: Text(name,
                      style: const TextStyle(
                          fontSize: 24, fontWeight: FontWeight.w800)),
                ),
                const SizedBox(height: 32),
                _ProfileTile(Icons.person_rounded,
                    tr(context, fr: 'Nom', ar: 'الاسم'), name),
                _ProfileTile(Icons.phone_rounded,
                    tr(context, fr: 'Téléphone', ar: 'الهاتف'), phone),
                _ProfileTile(Icons.email_rounded,
                    tr(context, fr: 'Email', ar: 'البريد الإلكتروني'), email),
                _ProfileTile(Icons.badge_rounded,
                    tr(context, fr: 'Identifiant de compte', ar: 'معرّف الحساب'),
                    accountId),
                const SizedBox(height: 24),
                ListTile(
                  leading: const Icon(Icons.language_rounded,
                      color: AppColors.primary),
                  title: Text(tr(context, fr: 'Langue', ar: 'اللغة')),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
                    showModalBottomSheet(
                      context: context,
                      showDragHandle: true,
                      builder: (_) => Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ListTile(
                            title: const Text('Français'),
                            onTap: () {
                              appLocale.value = const Locale('fr');
                              Navigator.pop(context);
                            },
                          ),
                          ListTile(
                            title: const Text('العربية'),
                            onTap: () {
                              appLocale.value = const Locale('ar');
                              Navigator.pop(context);
                            },
                          ),
                        ],
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.support_agent_rounded,
                      color: AppColors.secondary),
                  title: Text(tr(context,
                      fr: 'Support & Réclamations', ar: 'الدعم والشكاوى')),
                  subtitle: Text(tr(context,
                      fr: 'Contacter l\'équipe Allo Service',
                      ar: 'تواصل مع فريق الدعم')),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => SupportScreen(
                        isPro: false,
                        senderName: name,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ProfileTile extends StatelessWidget {
  const _ProfileTile(this.icon, this.label, this.value);

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 13)),
                Text(value,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
