import 'package:flutter/material.dart';

import 'package:allo_service_pro/core/theme/app_colors.dart';
import 'package:allo_service_pro/features/notifications/application/notification_store.dart';
import 'package:allo_service_pro/features/notifications/domain/notification_model.dart';
import 'package:allo_service_pro/shared/app_locale.dart';
import 'package:allo_service_pro/shared/widgets/empty_state_widget.dart';

/// Notifications inbox — reads straight from [NotificationStore].
class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  IconData _iconFor(String type) {
    switch (type) {
      case 'chat':
        return Icons.chat_bubble_rounded;
      case 'request':
        return Icons.receipt_long_rounded;
      case 'system':
        return Icons.verified_user_rounded;
      default:
        return Icons.notifications_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(tr(context, fr: 'Notifications', ar: 'الإشعارات')),
        actions: [
          ValueListenableBuilder<List<NotificationModel>>(
            valueListenable: NotificationStore.notifications,
            builder: (_, list, __) {
              final hasUnread = list.any((n) => !n.isRead);
              if (!hasUnread) return const SizedBox.shrink();
              return TextButton(
                onPressed: () async {
                  for (final n in list.where((n) => !n.isRead)) {
                    await Future<void>.delayed(Duration.zero);
                    NotificationStore.markAsRead(n.id);
                  }
                },
                child: Text(tr(context,
                    fr: 'Tout lire', ar: 'قراءة الكل')),
              );
            },
          ),
        ],
      ),
      body: ValueListenableBuilder<List<NotificationModel>>(
        valueListenable: NotificationStore.notifications,
        builder: (_, list, __) {
          if (list.isEmpty) {
            return EmptyStateWidget(
              icon: Icons.notifications_none_rounded,
              title: tr(context, fr: 'Aucune notification', ar: 'لا إشعارات'),
              message: tr(context,
                  fr: 'Les activités de vos demandes apparaîtront ici.',
                  ar: 'نشاط طلباتك بيظهر هنا.'),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final n = list[i];
              return Container(
                decoration: BoxDecoration(
                  color: n.isRead ? Colors.white : AppColors.primarySurface,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: ListTile(
                  leading: Icon(_iconFor(n.type),
                      color: AppColors.primary, size: 26),
                  title: Text(n.title,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(n.message,
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                  trailing: n.isRead
                      ? null
                      : Container(
                          width: 10,
                          height: 10,
                          decoration: const BoxDecoration(
                              color: AppColors.secondary,
                              shape: BoxShape.circle),
                        ),
                  onTap: () => NotificationStore.markAsRead(n.id),
                ),
              );
            },
          );
        },
      ),
    );
  }
}