import 'package:flutter/material.dart';

import 'package:allo_service_pro/core/theme/app_colors.dart';

/// Static, NON-CLICKABLE Support block placed directly above the Sign-Out /
/// Logout button on the client and professional settings screens.
///
/// No [InkWell], no [GestureDetector], no launcher actions: the email and
/// phone are presented as read-only reference text so users always know how
/// to reach support without the widget ever intercepting a tap.
///
/// The email is wrapped in a [FittedBox] (`BoxFit.scaleDown`) so the long
/// address shrinks to fit narrow screens instead of overflowing, and the
/// phone is constrained with `TextOverflow.ellipsis` as belt-and-braces.
class SupportInfo extends StatelessWidget {
  const SupportInfo({super.key});

  @override
  Widget build(BuildContext context) {
    // Outer container: light surface, subtle border, rounded corners —
    // visually grouped with the Sign-Out tile that follows it.
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        // Subtle border: AppColors has no slate200, so emit a light
        // blue-grey directly (avoids a new palette entry / lint warning).
        border: Border.all(color: const Color(0xFFCBD5E1), width: 1),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        // Vertical Column, centered — matches the requested structure.
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Header: "Support" — primary blue, medium size.
          Text(
            'Support',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.primary,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 6),
          // Email: wrapped so it can NEVER overflow horizontally.
          SizedBox(
            width: double.infinity,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                'support.alloservice@gmail.com',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 13,
                ),
              ),
            ),
          ),
          const SizedBox(height: 2),
          // Phone: ellipsis overflow guard.
          Text(
            '24449959',
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
