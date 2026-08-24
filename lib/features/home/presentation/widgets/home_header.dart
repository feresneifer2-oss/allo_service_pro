import 'package:flutter/material.dart';
import '../../../../shared/app_locale.dart';

class HomeHeader extends StatelessWidget {
  final String userName;

  const HomeHeader({
    super.key,
    required this.userName,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CircleAvatar(
          radius: 26,
          backgroundColor: const Color(0xFFEFF6FF),
          child: Text(
            userName.substring(0, 1).toUpperCase(),
            style: const TextStyle(
              color: Color(0xFF2563EB),
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
                style:
                    const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: () {
            showModalBottomSheet(
              context: context,
              showDragHandle: true,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              builder: (_) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(
                      title: const Text("Français"),
                      onTap: () {
                        appLocale.value = const Locale('fr');
                        Navigator.pop(context);
                      },
                    ),
                    ListTile(
                      title: const Text("العربية"),
                      onTap: () {
                        appLocale.value = const Locale('ar');
                        Navigator.pop(context);
                      },
                    ),
                    const SizedBox(height: 10),
                  ],
                );
              },
            );
          },
          icon: const Icon(Icons.language_rounded),
        ),
        Stack(
          children: [
            IconButton(
              onPressed: () {
                showModalBottomSheet<void>(
                  context: context,
                  showDragHandle: true,
                  builder: (sheetContext) => SafeArea(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(24, 8, 24, 32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.notifications_none_rounded,
                              size: 48),
                          const SizedBox(height: 12),
                          Text(
                            tr(context,
                                fr: 'Aucune nouvelle notification',
                                ar: 'لا توجد إشعارات جديدة'),
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            tr(context,
                                fr: "Vous êtes à jour !",
                                ar: "أنت على اطلاع بكل جديد!"),
                            style: const TextStyle(
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.notifications_none_rounded),
            ),
            Positioned(
              right: 10,
              top: 10,
              child: Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                    color: Colors.red, shape: BoxShape.circle),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
