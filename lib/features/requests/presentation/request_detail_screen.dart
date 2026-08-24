import 'package:flutter/material.dart';

import 'package:allo_service_pro/core/models/request_status.dart';
import 'package:allo_service_pro/core/theme/app_colors.dart';
import 'package:allo_service_pro/features/chat/application/chat_store.dart';
import 'package:allo_service_pro/features/chat/presentation/chat_screen.dart';
import 'package:allo_service_pro/features/rating/presentation/rating_screen.dart';
import 'package:allo_service_pro/features/requests/application/request_store.dart';
import 'package:allo_service_pro/features/requests/models/service_request.dart';
import 'package:allo_service_pro/shared/app_locale.dart';
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
                  _InfoCard(
                    icon: Icons.calendar_month_rounded,
                    label:
                        tr(context, fr: 'Date & Heure', ar: 'التاريخ والوقت'),
                    value: '$date • $time',
                  ),
                  _InfoCard(
                    icon: Icons.location_on_rounded,
                    label: tr(context, fr: 'Lieu', ar: 'المكان'),
                    value: request.address,
                  ),
                  if (request.message.isNotEmpty)
                    _InfoCard(
                      icon: Icons.message_rounded,
                      label: tr(context, fr: 'Message', ar: 'الرسالة'),
                      value: request.message,
                    ),
                  const SizedBox(height: 24),
                  if (RequestStore.isChatAllowed(request.id))
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          ChatStore.seedDemo(request.id);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ChatScreen(requestId: request.id),
                            ),
                          );
                        },
                        icon: const Icon(Icons.chat_rounded),
                        label: Text(tr(context,
                            fr: 'Ouvrir le chat', ar: 'فتح المحادثة')),
                      ),
                    ),
                  if (request.status == RequestStatus.completed &&
                      request.rating == null) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  RatingScreen(requestId: request.id),
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.secondary),
                        icon: const Icon(Icons.star_rounded),
                        label: Text(
                          tr(context, fr: 'Évaluer', ar: 'قيّم'),
                        ),
                      ),
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

class _InfoCard extends StatelessWidget {
  const _InfoCard(
      {required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        color: Color(0xFF94A3B8), fontSize: 13)),
                const SizedBox(height: 4),
                Text(value,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
