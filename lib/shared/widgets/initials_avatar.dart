import 'package:flutter/material.dart';

import 'package:allo_service_pro/core/theme/app_colors.dart';

/// Avatar showing the uppercased first character of [name].
///
/// Null/empty/whitespace-only names safely fall back to `?` instead of
/// throwing a RangeError — centralizes the guard previously copy-pasted
/// across profile, messaging and search screens.
class InitialsAvatar extends StatelessWidget {
  const InitialsAvatar({
    super.key,
    required this.name,
    this.radius = 24,
    this.backgroundColor = AppColors.primarySurface,
    this.textStyle,
  });

  final String name;
  final double radius;
  final Color? backgroundColor;

  /// Optional full override; defaults to a bold label sized relative to
  /// [radius] using the theme's on-surface color.
  final TextStyle? textStyle;

  String get _initial {
    final trimmed = name.trim();
    return (trimmed.isNotEmpty ? trimmed[0] : '?').toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: backgroundColor,
      child: Text(
        _initial,
        style: (textStyle ??
                TextStyle(
                  fontSize: radius * .75,
                  fontWeight: FontWeight.w700,
                ))
            .copyWith(),
      ),
    );
  }
}