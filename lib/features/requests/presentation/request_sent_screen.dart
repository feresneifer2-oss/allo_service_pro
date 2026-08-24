import 'package:flutter/material.dart';

import 'package:allo_service_pro/core/models/request_status.dart';
import 'package:allo_service_pro/core/theme/app_colors.dart';
import 'package:allo_service_pro/features/requests/application/request_store.dart';
import 'package:allo_service_pro/features/requests/presentation/request_detail_screen.dart';
import 'package:allo_service_pro/shared/app_locale.dart';
import 'package:allo_service_pro/shared/widgets/status_badge.dart';

class RequestSentScreen extends StatelessWidget {
  const RequestSentScreen({super.key, required this.requestId});

  final String requestId;

  @override
  Widget build(BuildContext context) {
    final request = RequestStore.byId(requestId);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Spacer(),
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: .15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_rounded,
                    color: AppColors.success, size: 48),
              ),
              const SizedBox(height: 24),
              Text(
                tr(context,
                    fr: 'Votre demande est envoyée', ar: 'تم إرسال طلبك'),
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              Text(
                tr(
                  context,
                  fr: 'Le professionnel va examiner votre demande.',
                  ar: 'المحترف سيراجع طلبك.',
                ),
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: AppColors.textSecondary, height: 1.5),
              ),
              const SizedBox(height: 20),
              if (request != null)
                const StatusBadge(status: RequestStatus.pending),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            RequestDetailScreen(requestId: requestId),
                      ),
                    );
                  },
                  child:
                      Text(tr(context, fr: 'Voir ma demande', ar: 'عرض طلبي')),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => Navigator.popUntil(context, (r) => r.isFirst),
                child: Text(tr(context,
                    fr: 'Retour à l\'accueil', ar: 'العودة للرئيسية')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
