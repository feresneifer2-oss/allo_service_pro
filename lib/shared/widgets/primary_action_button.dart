import 'package:flutter/material.dart';

import 'package:allo_service_pro/core/theme/app_colors.dart';

/// Standard full-width action button used across feature screens.
///
/// Wraps [ElevatedButton] / [ElevatedButton.icon] with the project's common
/// sizing (full width, fixed height) so screens stay consistent and callers
/// only pass a localized [label].
class PrimaryActionButton extends StatelessWidget {
  const PrimaryActionButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.height = 52,
    this.backgroundColor = AppColors.primary,
    this.foregroundColor,
    this.expandWidth = true,
  });

  /// Localized label (callers resolve it with `tr(...)`).
  final String label;
  final VoidCallback? onPressed;

  /// Optional leading icon — renders an `.icon` variant when provided.
  final IconData? icon;
  final double height;
  final Color? backgroundColor;

  /// Optional explicit label/icon color (defaults to the theme's on-primary).
  final Color? foregroundColor;

  /// When true (default) the button stretches to full available width.
  final bool expandWidth;

  @override
  Widget build(BuildContext context) {
    final style = ElevatedButton.styleFrom(
      backgroundColor: backgroundColor,
      foregroundColor: foregroundColor,
    );

    Widget button;
    if (icon != null) {
      button = ElevatedButton.icon(
        onPressed: onPressed,
        style: style,
        icon: Icon(icon),
        label: Text(label),
      );
    } else {
      button = ElevatedButton(
        onPressed: onPressed,
        style: style,
        child: Text(label),
      );
    }

    return SizedBox(
      width: expandWidth ? double.infinity : null,
      height: height,
      child: button,
    );
  }
}