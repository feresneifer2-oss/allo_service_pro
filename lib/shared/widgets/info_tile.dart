import 'package:flutter/material.dart';

import 'package:allo_service_pro/core/theme/app_colors.dart';

/// Visual density of an [InfoTile].
enum InfoTileVariant {
  /// White card on light backgrounds (e.g. customer profile).
  light,

  /// Slate card on dark backgrounds (e.g. request detail).
  dark,
}

/// Icon + label + value row rendered inside a rounded card.
///
/// Unifies the private `_ProfileTile` / `_InfoCard` copies previously
/// duplicated across profile and request screens.
class InfoTile extends StatelessWidget {
  const InfoTile({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.variant = InfoTileVariant.light,
  });

  final IconData icon;
  final String label;
  final String value;
  final InfoTileVariant variant;

  @override
  Widget build(BuildContext context) {
    final bool isDark = variant == InfoTileVariant.dark;

    final Color cardColor =
        isDark ? const Color(0xFF1E293B) : Colors.white;
    final Color labelColor =
        isDark ? const Color(0xFF94A3B8) : AppColors.textSecondary;
    final Color valueColor = isDark ? Colors.white : AppColors.textPrimary;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
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
                Text(
                  label,
                  style: TextStyle(color: labelColor, fontSize: 13),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(
                    color: valueColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}