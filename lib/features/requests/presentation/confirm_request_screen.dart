import 'package:flutter/material.dart';

import 'package:allo_service_pro/core/theme/app_colors.dart';
import 'package:allo_service_pro/features/requests/application/request_store.dart';
import 'package:allo_service_pro/features/requests/models/service_request.dart';
import 'package:allo_service_pro/features/requests/presentation/request_sent_screen.dart';
import 'package:allo_service_pro/shared/app_locale.dart';

class ConfirmRequestScreen extends StatefulWidget {
  const ConfirmRequestScreen({super.key, required this.request});

  final ServiceRequest request;

  @override
  State<ConfirmRequestScreen> createState() => _ConfirmRequestScreenState();
}

class _ConfirmRequestScreenState extends State<ConfirmRequestScreen> {
  bool _isSubmitting = false;

  @override
  Widget build(BuildContext context) {
    final request = widget.request;
    final service =
        tr(context, fr: request.serviceTitleFr, ar: request.serviceTitleAr);
    final date =
        '${request.dateTime.day}/${request.dateTime.month}/${request.dateTime.year}';
    final time =
        '${request.dateTime.hour.toString().padLeft(2, '0')}:${request.dateTime.minute.toString().padLeft(2, '0')}';

    return Scaffold(
      backgroundColor: AppColors.slate900,
      appBar: AppBar(
        backgroundColor: AppColors.slate800,
        title: Text(tr(context, fr: 'Récapitulatif', ar: 'ملخص'),
            style: const TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
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
              const SizedBox(height: 8),
              // ── Payment: STRICTLY CASH (non-interactive badge) ─────────
              // D17 / Flouci selectors were removed: the professional
              // collects the payment in cash at the end of the service.
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.slate800,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: AppColors.secondary.withValues(alpha: .4)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.payments_rounded,
                        color: AppColors.secondary, size: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tr(context,
                                fr: 'Mode de paiement', ar: 'طريقة الدفع'),
                            style: const TextStyle(
                                color: AppColors.slate400, fontSize: 13),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            tr(context,
                                fr: 'Paiement en espèces',
                                ar: 'نقداً عند التنفيذ'),
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _isSubmitting
                      ? null
                      : () async {
                          if (_isSubmitting) return;
                          setState(() => _isSubmitting = true);
                          // Cash-only policy: the method is hardcoded server-side
                          // (locally) — no interactive selection anymore.
                          // AWAITED (CodeRabbit): the Supabase mirror settles
                          // before the user is told the order was sent.
                          final mirrored = await RequestStore.add(
                            request.copyWith(paymentMethod: 'cash'),
                          );
                          // ASYNC-GAP SAFETY: never navigate with a dead context.
                          if (!context.mounted) return;
                          if (!mirrored) {
                            // BACKEND REFUSAL (CodeRabbit): the order lives
                            // LOCAL-ONLY — the success screen would lie about
                            // the pro having received it. Re-arm the button so
                            // the same draft can be retried.
                            setState(() => _isSubmitting = false);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(tr(
                                  context,
                                  fr: "Demande enregistrée sur cet appareil, mais la synchronisation a échoué. Réessayez.",
                                  ar: 'تم حفظ الطلب على هذا الجهاز، لكن فشلت المزامنة. حاول مجدداً.',
                                )),
                                backgroundColor: AppColors.error,
                              ),
                            );
                            return;
                          }
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
          color: AppColors.slate800,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style:
                    const TextStyle(color: AppColors.slate400, fontSize: 13)),
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
