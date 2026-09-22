import 'package:flutter/material.dart';
import 'package:allo_service_pro/core/theme/app_colors.dart';
import 'package:allo_service_pro/features/notifications/application/notification_store.dart';
import 'package:allo_service_pro/features/notifications/presentation/notifications_screen.dart';
import '../../../../shared/app_locale.dart';

class HomeHeader extends StatelessWidget {
  final String userName;

  const HomeHeader({
    super.key,
    required this.userName,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: AppColors.primarySurface,
              child: Text(
                userName.isNotEmpty ? userName[0].toUpperCase() : '?',
                style: const TextStyle(
                  color: AppColors.blue600,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr(context, fr: "Bonjour 👋", ar: "مرحبا 👋"),
                    style: const TextStyle(color: Colors.grey, fontSize: 14),
                  ),
                  Text(
                    userName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: () => _pickLanguage(context),
              icon: const Icon(Icons.language_rounded),
            ),
            // Real notification bell: live unread badge + actual inbox.
            ValueListenableBuilder(
              valueListenable: NotificationStore.notifications,
              builder: (context, List notifications, _) {
                // Role-routed badge: only notifications addressed to the
                // CURRENT role (client / professional) count here.
                final unread =
                    NotificationStore.getNotificationsForCurrentUser()
                        .where((n) => !n.isRead)
                        .length;
                return Stack(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const NotificationsScreen(),
                        ),
                      ),
                      icon: const Icon(Icons.notifications_none_rounded),
                    ),
                    if (unread > 0)
                      Positioned(
                        right: 6,
                        top: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          constraints: const BoxConstraints(minWidth: 16),
                          decoration: BoxDecoration(
                            color: AppColors.error,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            unread > 99 ? '99+' : '$unread',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ],
    );
  }

  void _pickLanguage(BuildContext context) {
    final currentCode = appLocale.value.languageCode;
    const options = <String, String>{
      'fr': 'Français',
      'ar': 'العربية',
    };
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final code in options.keys)
              ListTile(
                leading: Icon(
                  code == currentCode
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_off_rounded,
                  color: AppColors.primary,
                ),
                title: Text(options[code]!),
                onTap: () {
                  setLocale(Locale(code));
                  Navigator.pop(sheetContext);
                },
              ),
            const SizedBox(height: 10),
          ],
        );
      },
    );
  }
}
