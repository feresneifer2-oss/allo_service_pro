import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // ─── Brand ───────────────────────────────────────────────────────────
  // STRICT palette: Blue · Orange · White · Slate neutrals only.

  static const Color primary = Color(0xFF1D4ED8);
  static const Color primaryLight = Color(0xFF3B82F6);
  static const Color primaryDark = Color(0xFF1E3A8A);
  static const Color blue600 = Color(0xFF2563EB);

  static const Color secondary = Color(0xFFF97316);
  static const Color secondaryLight = Color(0xFFFB923C);
  static const Color secondaryDark = Color(0xFFEA580C);

  // ─── Surfaces ────────────────────────────────────────────────────────
  static const Color background = Color(0xFFF8FAFC);
  static const Color surface = Colors.white;
  static const Color primarySurface = Color(0xFFEFF6FF);
  static const Color secondarySurface = Color(0xFFFFF7ED);

  // ─── Dark slate surfaces (dark screens) ──────────────────────────────
  static const Color slate900 = Color(0xFF0F172A);
  static const Color slate800 = Color(0xFF1E293B);
  static const Color slate400 = Color(0xFF94A3B8);

  // ─── Text ────────────────────────────────────────────────────────────
  static const Color textPrimary = Color(0xFF1E293B);
  static const Color textSecondary = Color(0xFF64748B);

  // ─── Semantic status ─────────────────────────────────────────────────
  static const Color success = Color(0xFF22C55E);
  static const Color warning = Color(0xFFF59E0B);
  static const Color error = Color(0xFFEF4444);

  // ─── Gradients ───────────────────────────────────────────────────────
  static const LinearGradient brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primary, primaryLight, Color(0xFF2563EB)],
  );

  static const LinearGradient accentGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [secondary, secondaryLight],
  );
}
