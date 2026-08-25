import 'package:flutter/material.dart';

import 'package:allo_service_pro/core/data/services_catalog.dart';
import 'package:allo_service_pro/core/theme/app_colors.dart';
import 'package:allo_service_pro/shared/app_locale.dart';

/// Urban-Company-style circular service tile.
///
/// Renders the downloaded PNG ([ServiceItem.imagePath]) clipped inside a
/// circle; when the local file is missing the standard [Icon]
/// (`ServiceItem.icon`) is rendered instead — the tile never breaks.
class ServiceCircleTile extends StatelessWidget {
  const ServiceCircleTile({
    super.key,
    required this.service,
    this.size = 64,
    this.showLabel = true,
    this.onTap,
  });

  final ServiceItem service;

  /// Diameter of the circle in logical pixels.
  final double size;
  final bool showLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final name = tr(context, fr: service.nameFr, ar: service.nameAr);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: size,
            height: size,
            decoration: const BoxDecoration(
              color: AppColors.primarySurface,
              shape: BoxShape.circle,
            ),
            clipBehavior: Clip.antiAlias,
            child: Image.asset(
              service.imagePath,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Icon(
                service.icon,
                color: AppColors.primary,
                size: size * .45,
              ),
            ),
          ),
          if (showLabel) ...[
            const SizedBox(height: 6),
            SizedBox(
              width: size * 1.7,
              child: Text(
                name,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}