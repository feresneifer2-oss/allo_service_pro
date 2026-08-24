import 'package:flutter/material.dart';
import 'app_colors.dart';

class AppThemeConstants {
  // Dark Theme Colors
  static const Color darkBackground = Color(0xFF0F172A);
  static const Color darkCardBackground = Color(0xFF1E293B);
  static const Color darkInputBackground = Color(0xFF1E293B);
  static const Color darkTextPrimary = Colors.white;
  static const Color darkTextSecondary = Color(0xFF94A3B8);
  static const Color darkTextTertiary = Color(0xFF64748B);

  // Light Theme Colors
  static const Color lightBackground = Color(0xFFF8FAFC);
  static const Color lightCardBackground = Colors.white;
  static const Color lightInputBackground = Color(0xFFF1F5F9);
  static const Color lightTextPrimary = Color(0xFF1E293B);
  static const Color lightTextSecondary = Color(0xFF64748B);
  static const Color lightTextTertiary = Color(0xFF94A3B8);

  // Status Colors
  static const Color statusPending = Color(0xFFF59E0B);
  static const Color statusAccepted = Color(0xFF10B981);
  static const Color statusCompleted = Color(0xFF3B82F6);
  static const Color statusRejected = Color(0xFFEF4444);
  static const Color statusCancelled = Color(0xFF6B7280);

  // Border Radius
  static const double borderRadiusSmall = 8.0;
  static const double borderRadiusMedium = 12.0;
  static const double borderRadiusLarge = 16.0;
  static const double borderRadiusXLarge = 18.0;
  static const double borderRadiusRound = 20.0;
  static const double borderRadiusCircle = 50.0;

  // Spacing
  static const double spacingXXS = 2.0;
  static const double spacingXS = 4.0;
  static const double spacingS = 8.0;
  static const double spacingM = 12.0;
  static const double spacingL = 16.0;
  static const double spacingXL = 24.0;
  static const double spacingXXL = 32.0;
  static const double spacingXXXL = 48.0;

  // Font Sizes
  static const double fontSizeXXS = 10.0;
  static const double fontSizeXS = 11.0;
  static const double fontSizeS = 12.0;
  static const double fontSizeM = 14.0;
  static const double fontSizeL = 16.0;
  static const double fontSizeXL = 18.0;
  static const double fontSizeXXL = 20.0;
  static const double fontSizeXXXL = 24.0;
  static const double fontSizeXXXXL = 28.0;
  static const double fontSizeXXXXXL = 32.0;

  // Icon Sizes
  static const double iconSizeXS = 14.0;
  static const double iconSizeS = 16.0;
  static const double iconSizeM = 20.0;
  static const double iconSizeL = 24.0;
  static const double iconSizeXL = 32.0;
  static const double iconSizeXXL = 48.0;
  static const double iconSizeXXXL = 64.0;

  // Avatar Sizes
  static const double avatarSizeS = 32.0;
  static const double avatarSizeM = 40.0;
  static const double avatarSizeL = 48.0;
  static const double avatarSizeXL = 56.0;
  static const double avatarSizeXXL = 72.0;

  // Elevations
  static const double elevationNone = 0.0;
  static const double elevationXS = 0.5;
  static const double elevationS = 1.0;
  static const double elevationM = 2.0;
  static const double elevationL = 4.0;
  static const double elevationXL = 8.0;

  // Opacity
  static const double opacityDisabled = 0.38;
  static const double opacityHover = 0.8;
  static const double opacityPressed = 0.6;
  static const double opacitySubtle = 0.7;

  // Durations
  static const Duration durationFast = Duration(milliseconds: 150);
  static const Duration durationNormal = Duration(milliseconds: 300);
  static const Duration durationSlow = Duration(milliseconds: 500);
  static const Duration durationVerySlow = Duration(milliseconds: 1000);

  // Screen Padding
  static const EdgeInsets screenPaddingM = EdgeInsets.all(spacingL);
  static const EdgeInsets screenPaddingL = EdgeInsets.all(spacingXL);
  static const EdgeInsets screenPaddingXL = EdgeInsets.all(spacingXXL);

  // Card Padding
  static const EdgeInsets cardPaddingS = EdgeInsets.all(spacingM);
  static const EdgeInsets cardPaddingM = EdgeInsets.all(spacingL);
  static const EdgeInsets cardPaddingL = EdgeInsets.all(spacingXL);

  // Text Styles
  static const TextStyle heading1 = TextStyle(
    fontSize: fontSizeXXXXXL,
    fontWeight: FontWeight.bold,
  );

  static const TextStyle heading2 = TextStyle(
    fontSize: fontSizeXXXXL,
    fontWeight: FontWeight.bold,
  );

  static const TextStyle heading3 = TextStyle(
    fontSize: fontSizeXXXL,
    fontWeight: FontWeight.bold,
  );

  static const TextStyle heading4 = TextStyle(
    fontSize: fontSizeXXL,
    fontWeight: FontWeight.bold,
  );

  static const TextStyle titleLarge = TextStyle(
    fontSize: fontSizeXL,
    fontWeight: FontWeight.w600,
  );

  static const TextStyle titleMedium = TextStyle(
    fontSize: fontSizeL,
    fontWeight: FontWeight.w600,
  );

  static const TextStyle titleSmall = TextStyle(
    fontSize: fontSizeM,
    fontWeight: FontWeight.w600,
  );

  static const TextStyle bodyLarge = TextStyle(
    fontSize: fontSizeL,
    fontWeight: FontWeight.normal,
  );

  static const TextStyle bodyMedium = TextStyle(
    fontSize: fontSizeM,
    fontWeight: FontWeight.normal,
  );

  static const TextStyle bodySmall = TextStyle(
    fontSize: fontSizeS,
    fontWeight: FontWeight.normal,
  );

  static const TextStyle caption = TextStyle(
    fontSize: fontSizeXS,
    fontWeight: FontWeight.normal,
  );

  // Button Heights
  static const double buttonHeightS = 40.0;
  static const double buttonHeightM = 48.0;
  static const double buttonHeightL = 56.0;

  // Input Heights
  static const double inputHeightS = 40.0;
  static const double inputHeightM = 48.0;
  static const double inputHeightL = 56.0;

  // Border Widths
  static const double borderWidthThin = 0.5;
  static const double borderWidthNormal = 1.0;
  static const double borderWidthThick = 2.0;

  // Input Decoration
  static InputDecoration darkInputDecoration({
    String? hintText,
    Widget? prefixIcon,
    Widget? suffixIcon,
    String? errorText,
  }) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: const TextStyle(color: darkTextSecondary),
      prefixIcon: prefixIcon,
      suffixIcon: suffixIcon,
      errorText: errorText,
      filled: true,
      fillColor: darkInputBackground,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(borderRadiusLarge),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(borderRadiusLarge),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(borderRadiusLarge),
        borderSide:
            BorderSide(color: AppColors.primary, width: borderWidthNormal),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(borderRadiusLarge),
        borderSide:
            const BorderSide(color: AppColors.error, width: borderWidthNormal),
      ),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: spacingL,
        vertical: 15,
      ),
    );
  }

  static InputDecoration lightInputDecoration({
    String? hintText,
    Widget? prefixIcon,
    Widget? suffixIcon,
    String? errorText,
  }) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: const TextStyle(color: lightTextSecondary),
      prefixIcon: prefixIcon,
      suffixIcon: suffixIcon,
      errorText: errorText,
      filled: true,
      fillColor: lightInputBackground,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(borderRadiusLarge),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(borderRadiusLarge),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(borderRadiusLarge),
        borderSide:
            BorderSide(color: AppColors.primary, width: borderWidthNormal),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(borderRadiusLarge),
        borderSide:
            const BorderSide(color: AppColors.error, width: borderWidthNormal),
      ),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: spacingL,
        vertical: 15,
      ),
    );
  }

  // Card Decoration
  static BoxDecoration darkCardDecoration({
    double borderRadius = borderRadiusXLarge,
    Color? borderColor,
    double borderWidth = borderWidthNormal,
  }) {
    return BoxDecoration(
      color: darkCardBackground,
      borderRadius: BorderRadius.circular(borderRadius),
      border: borderColor != null
          ? Border.all(color: borderColor, width: borderWidth)
          : null,
    );
  }

  static BoxDecoration lightCardDecoration({
    double borderRadius = borderRadiusXLarge,
    Color? borderColor,
    double borderWidth = borderWidthNormal,
  }) {
    return BoxDecoration(
      color: lightCardBackground,
      borderRadius: BorderRadius.circular(borderRadius),
      border: borderColor != null
          ? Border.all(color: borderColor, width: borderWidth)
          : null,
    );
  }

  // Chip Decoration
  static BoxDecoration darkChipDecoration({
    bool isSelected = false,
  }) {
    return BoxDecoration(
      color: isSelected ? AppColors.secondary : const Color(0xFF0F172A),
      borderRadius: BorderRadius.circular(borderRadiusRound),
      border: Border.all(
        color: isSelected ? AppColors.secondary : const Color(0xFF334155),
      ),
    );
  }

  static BoxDecoration lightChipDecoration({
    bool isSelected = false,
  }) {
    return BoxDecoration(
      color: isSelected ? AppColors.secondary : const Color(0xFFF1F5F9),
      borderRadius: BorderRadius.circular(borderRadiusRound),
      border: Border.all(
        color: isSelected ? AppColors.secondary : const Color(0xFFE2E8F0),
      ),
    );
  }

  // Button Styles
  static ButtonStyle primaryButtonStyle = ElevatedButton.styleFrom(
    backgroundColor: AppColors.primary,
    foregroundColor: Colors.white,
    elevation: elevationNone,
    padding:
        const EdgeInsets.symmetric(horizontal: spacingXL, vertical: spacingM),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(borderRadiusLarge),
    ),
  );

  static ButtonStyle secondaryButtonStyle = ElevatedButton.styleFrom(
    backgroundColor: AppColors.secondary,
    foregroundColor: Colors.white,
    elevation: elevationNone,
    padding:
        const EdgeInsets.symmetric(horizontal: spacingXL, vertical: spacingM),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(borderRadiusLarge),
    ),
  );

  static ButtonStyle outlineButtonStyle = OutlinedButton.styleFrom(
    foregroundColor: AppColors.primary,
    side: const BorderSide(color: AppColors.primary),
    padding:
        const EdgeInsets.symmetric(horizontal: spacingXL, vertical: spacingM),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(borderRadiusLarge),
    ),
  );

  static ButtonStyle textButtonStyle = TextButton.styleFrom(
    foregroundColor: AppColors.primary,
    padding:
        const EdgeInsets.symmetric(horizontal: spacingL, vertical: spacingM),
  );
}
