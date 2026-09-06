import 'package:flutter/material.dart';

class AppDesignTokens {
  // Background & Surfaces (Clean white/light system inspired by modern POS dashboards)
  static const Color background = Color(0xFFF6F8FC);
  static const Color canvas = background;
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceCard = Color(0xFFFFFFFF);
  static const Color surfaceSecondary = Color(0xFFF9FAFB);
  static const Color surfaceElevated = Color(0xFFFFFFFF);
  static const Color surfaceInput = Color(0xFFFFFFFF);
  static const Color surfaceHighlight = Color(0xFFF1F5F9);

  // Borders
  static const Color border = Color(0xFFE5E7EB);
  static const Color borderSubtle = Color(0xFFF3F4F6);
  static const Color borderFocused = Color(0xFF2563EB);

  // Brand & Action Accents
  static const Color primary = Color(0xFF2563EB); // Modern cobalt blue
  static const Color primaryLight = Color(0xFF3B82F6);
  static const Color primaryHover = Color(0xFF1D4ED8);
  static const Color primaryDark = Color(0xFF1D4ED8);
  static const Color accentOrange = Color(
    0xFFF97316,
  ); // High-priority CTA (e.g. final payment)
  static const Color accentOrangeHover = Color(0xFFEA580C);

  // Semantic Feedback
  static const Color success = Color(0xFF10B981); // Emerald green
  static const Color successBg = Color(0xFFECFDF5);
  static const Color successText = Color(0xFF065F46);

  static const Color warning = Color(0xFFF59E0B); // Amber
  static const Color warningBg = Color(0xFFFFFBEB);
  static const Color warningText = Color(0xFF92400E);

  static const Color danger = Color(0xFFEF4444); // Crimson red
  static const Color dangerBg = Color(0xFFFEF2F2);
  static const Color dangerText = Color(0xFF991B1B);

  static const Color error = danger;
  static const Color errorBg = dangerBg;
  static const Color errorText = dangerText;

  // Typography
  static const Color textPrimary = Color(
    0xFF111827,
  ); // Deep dark slate (no pure black)
  static const Color textSecondary = Color(0xFF667085); // Slate gray
  static const Color textMuted = Color(
    0xFF98A2B3,
  ); // Soft placeholder & helper text

  // Spacing Scale
  static const double space2 = 2;
  static const double space4 = 4;
  static const double space8 = 8;
  static const double space12 = 12;
  static const double space16 = 16;
  static const double space20 = 20;
  static const double space24 = 24;
  static const double space32 = 32;
  static const double space40 = 40;

  // Corner Radii (8px inputs/buttons, 10-12px cards, 14px dialogs)
  static const double radiusSm = 6;
  static const double radiusMd = 8;
  static const double radiusLg = 12;
  static const double radiusXl = 14;
  static const double radiusSmall = radiusSm;
  static const double radiusMedium = radiusMd;
  static const double radiusLarge = radiusLg;
  static const double radiusCard = radiusLg;
  static const double radiusDialog = radiusXl;
  static const double radiusInput = radiusMd;

  // Heights
  static const double buttonHeightSm = 36;
  static const double buttonHeightMd = 42;
  static const double buttonHeightLg = 50;
  static const double inputHeight = 42;

  // Subtle Depth / Soft Shadows
  static List<BoxShadow> get shadowSm => [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.04),
      blurRadius: 3,
      offset: const Offset(0, 1),
    ),
  ];

  static List<BoxShadow> get shadowMd => [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.05),
      blurRadius: 8,
      offset: const Offset(0, 2),
    ),
  ];

  static List<BoxShadow> get shadowLg => [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.08),
      blurRadius: 16,
      offset: const Offset(0, 4),
    ),
  ];
}
