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

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  void _submit() {
    RequestStore.rate(
        widget.requestId, _stars.toDouble(), _commentController.text.trim());
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(tr(context,
            fr: 'Merci pour votre avis !', ar: 'شكراً على تقييمك!')),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
            tr(context, fr: 'Évaluez votre expérience', ar: 'قيّم تجربتك')),
      ),
      body: SafeArea(
        child: ListView(
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
                onPressed: _submit,
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.secondary),
                child: Text(tr(context, fr: 'Envoyer', ar: 'إرسال')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
