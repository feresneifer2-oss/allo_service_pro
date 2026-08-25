import 'package:flutter/material.dart';

import 'package:allo_service_pro/core/theme/app_colors.dart';
import 'package:allo_service_pro/features/auth/application/user_store.dart';
import 'package:allo_service_pro/features/chat/application/chat_store.dart';
import 'package:allo_service_pro/features/chat/models/chat_session.dart';
import 'package:allo_service_pro/features/chat/presentation/chat_screen.dart';
import 'package:allo_service_pro/features/notifications/application/notification_store.dart';
import 'package:allo_service_pro/features/notifications/presentation/notifications_screen.dart';
import 'package:allo_service_pro/shared/widgets/empty_state_widget.dart';
import 'package:allo_service_pro/features/requests/application/request_store.dart';
import 'package:allo_service_pro/features/requests/models/service_request.dart';
import 'package:allo_service_pro/features/support/presentation/support_screen.dart';
import 'package:allo_service_pro/shared/app_locale.dart' show appLocale, tr;
import 'package:allo_service_pro/shared/widgets/info_tile.dart';
import 'package:allo_service_pro/shared/widgets/initials_avatar.dart';

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
                child: EmptyStateWidget(
                  icon: Icons.chat_bubble_outline_rounded,
                  title: tr(context, fr: 'Aucun message', ar: 'لا رسائل'),
                  message: tr(context,
                      fr: 'Vos conversations apparaîtront ici.',
                      ar: 'محادثاتك بتظهر هنا.'),
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
                  leading: InitialsAvatar(
                    name: r.professionalName,
                    backgroundColor: AppColors.primarySurface,
                    textStyle: const TextStyle(color: AppColors.primary),
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
                  child: InitialsAvatar(
                    name: name,
                    radius: 48,
                    backgroundColor: AppColors.primarySurface,
                    textStyle: const TextStyle(
                        fontSize: 36,
                        color: AppColors.primary,
                        fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 16),
                Center(
                  child: Text(name,
                      style: const TextStyle(
                          fontSize: 24, fontWeight: FontWeight.w800)),
                ),
                const SizedBox(height: 32),
                InfoTile(
                  icon: Icons.person_rounded,
                  label: tr(context, fr: 'Nom', ar: 'الاسم'),
                  value: name,
                ),
                InfoTile(
                  icon: Icons.phone_rounded,
                  label: tr(context, fr: 'Téléphone', ar: 'الهاتف'),
                  value: phone,
                ),
                InfoTile(
                  icon: Icons.email_rounded,
                  label: tr(context, fr: 'Email', ar: 'البريد الإلكتروني'),
                  value: email,
                ),
                InfoTile(
                  icon: Icons.badge_rounded,
                  label: tr(context, fr: 'Identifiant de compte', ar: 'معرّف الحساب'),
                  value: accountId,
                ),
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
                ValueListenableBuilder(
                  valueListenable: NotificationStore.notifications,
                  builder: (_, list, __) {
                    final dynamic items = list;
                    final unread = items.where((n) => !n.isRead).length;
                    return ListTile(
                      leading: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          const Icon(Icons.notifications_rounded,
                              color: AppColors.primary),
                          if (unread > 0)
                            Positioned(
                              right: -2,
                              top: -2,
                              child: Container(
                                width: 10,
                                height: 10,
                                decoration: const BoxDecoration(
                                  color: AppColors.secondary,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                        ],
                      ),
                      title: Text(tr(context,
                          fr: 'Notifications', ar: 'الإشعارات')),
                      subtitle: unread > 0
                          ? Text(tr(context,
                              fr: '$unread non lue(s)',
                              ar: '$unread غير مقروءة'))
                          : null,
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const NotificationsScreen(),
                        ),
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
