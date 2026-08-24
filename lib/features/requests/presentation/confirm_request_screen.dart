import 'package:flutter/material.dart';

import 'package:allo_service_pro/core/theme/app_colors.dart';
import 'package:allo_service_pro/features/requests/application/request_store.dart';
import 'package:allo_service_pro/features/requests/models/service_request.dart';
import 'package:allo_service_pro/features/requests/presentation/request_sent_screen.dart';
import 'package:allo_service_pro/shared/app_locale.dart';

class ConfirmRequestScreen extends StatelessWidget {
  const ConfirmRequestScreen({super.key, required this.request});

  final ServiceRequest request;

  @override
  Widget build(BuildContext context) {
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
        title: Text(tr(context, fr: 'Récapitulatif', ar: 'ملخص'),
            style: const TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr(context, fr: 'Votre demande', ar: 'طلبك'),
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 24),
              _Row(tr(context, fr: 'Service', ar: 'الخدمة'), service),
              _Row(tr(context, fr: 'Professionnel', ar: 'المحترف'),
                  request.professionalName),
              _Row(tr(context, fr: 'Date', ar: 'التاريخ'), date),
              _Row(tr(context, fr: 'Heure', ar: 'الوقت'), time),
              _Row(tr(context, fr: 'Lieu', ar: 'المكان'), request.address),
              if (request.message.isNotEmpty)
                _Row(
                    tr(context, fr: 'Message', ar: 'الرسالة'), request.message),
              if (request.photoPaths.isNotEmpty)
                _Row(
                  tr(context, fr: 'Photos', ar: 'الصور'),
                  '${request.photoPaths.length}',
                ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: () {
                    RequestStore.add(request);
                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            RequestSentScreen(requestId: request.id),
                      ),
                      (r) => r.isFirst,
                    );
                  },
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.secondary),
                  child: Text(
                      tr(context, fr: 'Envoyer la demande', ar: 'إرسال الطلب')),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
            const SizedBox(height: 4),
            Text(value,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 16)),
          ],
        ),
      ),
    );
  }
}
