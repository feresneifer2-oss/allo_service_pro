import 'package:flutter/material.dart';

import 'package:allo_service_pro/core/models/request_status.dart';
import 'package:allo_service_pro/core/theme/app_colors.dart';
import 'package:allo_service_pro/features/chat/application/chat_store.dart';
import 'package:allo_service_pro/features/chat/presentation/chat_screen.dart';
import 'package:allo_service_pro/features/rating/presentation/rating_screen.dart';
import 'package:allo_service_pro/features/requests/application/request_store.dart';
import 'package:allo_service_pro/features/requests/models/service_request.dart';
import 'package:allo_service_pro/shared/app_locale.dart';
import 'package:allo_service_pro/shared/widgets/info_tile.dart';
import 'package:allo_service_pro/shared/widgets/primary_action_button.dart';
import 'package:allo_service_pro/shared/widgets/status_badge.dart';

class RequestDetailScreen extends StatelessWidget {
  const RequestDetailScreen({super.key, required this.requestId});

  final String requestId;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<ServiceRequest>>(
      valueListenable: RequestStore.requests,
      builder: (context, _, __) {
        final request = RequestStore.byId(requestId);
        if (request == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: Text('Request not found')),
          );
        }

        final service =
            tr(context, fr: request.serviceTitleFr, ar: request.serviceTitleAr);
        final date =
            '${request.dateTime.day}/${request.dateTime.month}/${request.dateTime.year}';
        final time =
            '${request.dateTime.hour.toString().padLeft(2, '0')}:${request.dateTime.minute.toString().padLeft(2, '0')}';

        return Scaffold(
          backgroundColor: const Color(0xFF0F172A),
          appBar: AppBar(
            backgroundColor: const Color(0xFF1E293B),
            title: Text(tr(context, fr: 'Ma demande', ar: 'طلبي')),
          ),
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          service,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w800),
                        ),
                      ),
                      StatusBadge(status: request.status),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    request.professionalName,
                    style:
                        const TextStyle(color: Color(0xFF94A3B8), fontSize: 16),
                  ),
                  const SizedBox(height: 24),
                  InfoTile(
                    icon: Icons.calendar_month_rounded,
                    variant: InfoTileVariant.dark,
                    label:
                        tr(context, fr: 'Date & Heure', ar: 'التاريخ والوقت'),
                    value: '$date • $time',
                  ),
                  InfoTile(
                    icon: Icons.location_on_rounded,
                    variant: InfoTileVariant.dark,
                    label: tr(context, fr: 'Lieu', ar: 'المكان'),
                    value: request.address,
                  ),
                  if (request.message.isNotEmpty)
                    InfoTile(
                      icon: Icons.message_rounded,
                      variant: InfoTileVariant.dark,
                      label: tr(context, fr: 'Message', ar: 'الرسالة'),
                      value: request.message,
                    ),
                  const SizedBox(height: 24),
                  if (RequestStore.isChatAllowed(request.id))
                    PrimaryActionButton(
                      label: tr(
                          context, fr: 'Ouvrir le chat', ar: 'فتح المحادثة'),
                      icon: Icons.chat_rounded,
                      onPressed: () {
                        ChatStore.seedDemo(request.id);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ChatScreen(requestId: request.id),
                          ),
                        );
                      },
                    ),
                  if (request.status == RequestStatus.completed &&
                      request.rating == null) ...[
                    const SizedBox(height: 12),
                    PrimaryActionButton(
                      label: tr(context, fr: 'Évaluer', ar: 'قيّم'),
                      icon: Icons.star_rounded,
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => RatingScreen(requestId: request.id),
                          ),
                        );
                      },
                      backgroundColor: AppColors.secondary,
                    ),
                  ],
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
