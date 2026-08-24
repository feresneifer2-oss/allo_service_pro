import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

class AlloServiceLogo extends StatelessWidget {
  const AlloServiceLogo({
    super.key,
    this.imageWidth = 170,
    this.showTagline = false,
  });

  final double imageWidth;
  final bool showTagline;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _LogoImage(width: imageWidth),
        if (showTagline) ...[
          const SizedBox(height: 12),
          Text(
            'Services professionnels en Tunisie',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textSecondary.withOpacity(.9),
              fontSize: 14,
            ),
          ),
        ],
      ],
    );
  }
}

class _LogoImage extends StatelessWidget {
  const _LogoImage({required this.width});

  final double width;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/logo.png',
      width: width,
      errorBuilder: (_, __, ___) => _TextLogo(width: width),
    );
  }
}

class _TextLogo extends StatelessWidget {
  const _TextLogo({required this.width});

  final double width;

  @override
  Widget build(BuildContext context) {
    final fontSize = (width / 170 * 32).clamp(24.0, 40.0);

    return SizedBox(
      width: width,
      child: RichText(
        textAlign: TextAlign.center,
        text: TextSpan(
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w800,
            fontFamily: 'Poppins',
            height: 1.1,
          ),
          children: const [
            TextSpan(
              text: 'ALLO ',
              style: TextStyle(color: AppColors.primary),
            ),
            TextSpan(
              text: 'SERVICE',
              style: TextStyle(color: AppColors.secondary),
            ),
          ],
        ),
      ),
    );
  }
}
