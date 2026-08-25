import 'package:flutter/material.dart';
import 'package:allo_service_pro/core/theme/app_colors.dart';

class ServiceCard extends StatelessWidget {
  final IconData icon;

  /// Optional local asset path (`assets/services/...`). When provided it
  /// replaces the plain icon inside the avatar (with icon fallback if the
  /// asset fails to load).
  final String? imagePath;
  final String title;
  final VoidCallback onTap;

  const ServiceCard({
    super.key,
    required this.icon,
    this.imagePath,
    required this.title,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: .05),
                blurRadius: 10,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: AppColors.primarySurface,
                child: imagePath == null
                    ? Icon(
                        icon,
                        color: AppColors.blue600,
                        size: 24,
                      )
                    : ClipOval(
                        child: Image.asset(
                          imagePath!,
                          width: 44,
                          height: 44,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Icon(
                            icon,
                            color: AppColors.blue600,
                            size: 24,
                          ),
                        ),
                      ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: Center(
                  child: Text(
                    title,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
