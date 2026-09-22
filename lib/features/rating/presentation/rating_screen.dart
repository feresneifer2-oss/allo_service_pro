import 'package:flutter/material.dart';

import 'package:allo_service_pro/core/theme/app_colors.dart';
import 'package:allo_service_pro/features/requests/application/request_store.dart';
import 'package:allo_service_pro/shared/app_locale.dart';

class RatingScreen extends StatefulWidget {
  const RatingScreen({super.key, required this.requestId});

  final String requestId;

  @override
  State<RatingScreen> createState() => _RatingScreenState();
}

class _RatingScreenState extends State<RatingScreen> {
  int _stars = 5;
  final _commentController = TextEditingController();

  /// SUBMISSION LOCK (CodeRabbit): true while a rating submission is in
  /// flight — double-taps on the button are ignored until it settles.
  bool _isSubmitting = false;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    // SUBMISSION LOCK (CodeRabbit): one review per tap — a double-tap on
    // the button while the (potentially backend-mirrored) submission is in
    // flight must never fire a second rating/update.
    if (_isSubmitting) return;
    _isSubmitting = true;
    try {
      // RATING GATE (CodeRabbit): `rate` now refuses anything that is not a
      // fully-completed order — a refusal must surface as an explicit error
      // state, never as a phantom thank-you.
      final ok = await RequestStore.rate(
          widget.requestId, _stars.toDouble(), _commentController.text.trim());
      if (!mounted) return;
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(tr(context,
                fr: 'Seuls les services terminés peuvent être évalués.',
                ar: 'يمكن تقييم الخدمات المكتملة فقط.')),
          ),
        );
        return;
      }
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(tr(context,
              fr: 'Merci pour votre avis !', ar: 'شكراً على تقييمك!')),
        ),
      );
    } finally {
      // Always re-arm, on every exit path (refusal, success, unmount race).
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
            tr(context, fr: 'Évaluez votre expérience', ar: 'قيّم تجربتك')),
      ),
      body: SafeArea(
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.all(24),
          children: [
            const Icon(Icons.check_circle_rounded,
                color: AppColors.success, size: 64),
            const SizedBox(height: 16),
            Text(
              tr(context, fr: 'Service terminé', ar: 'الخدمة مكتملة'),
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (i) {
                return IconButton(
                  onPressed: () => setState(() => _stars = i + 1),
                  icon: Icon(
                    i < _stars
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                    color: AppColors.secondary,
                    size: 40,
                  ),
                );
              }),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _commentController,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: tr(context,
                    fr: 'Commentaire (optionnel)', ar: 'تعليق (اختياري)'),
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _submit,
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.secondary),
                child: _isSubmitting
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.4, color: Colors.white),
                      )
                    : Text(tr(context, fr: 'Envoyer', ar: 'إرسال')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
