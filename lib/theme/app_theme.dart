import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ============================================================================
// CosmicGuide design system.
//
// One source of truth for colour, type, spacing, radius and elevation. Screens
// should read from these tokens instead of hard-coding `Color(0x...)` values so
// the whole app looks like one product (clean white surfaces, one saffron
// accent, deep-indigo "cosmic" hero areas).
// ============================================================================

class AppColors {
  AppColors._();

  // Brand
  static const primary = Color(0xFFFF6A13); // saffron: CTAs, active states
  static const primaryDark = Color(0xFFE5560A);
  static const primarySoft = Color(0xFFFFF1E8); // tinted backgrounds
  static const cosmic = Color(0xFF1B1446); // deep indigo: hero / AI areas
  static const cosmicLight = Color(0xFF2E2275);
  static const gold = Color(0xFFF5B83D);

  // Neutrals
  static const background = Color(0xFFF6F6F9);
  static const surface = Colors.white;
  static const surfaceMuted = Color(0xFFF1F1F5);
  static const border = Color(0xFFE9E9EF);
  static const divider = Color(0xFFF0F0F4);

  // Text
  static const textPrimary = Color(0xFF14142B);
  static const textSecondary = Color(0xFF5E5E74);
  static const textTertiary = Color(0xFF9696A8);
  static const textOnDark = Colors.white;
  static const textOnDarkMuted = Color(0xB3FFFFFF);

  // Semantic
  static const success = Color(0xFF16A34A);
  static const successSoft = Color(0xFFE8F7EE);
  static const warning = Color(0xFFF59E0B);
  static const warningSoft = Color(0xFFFFF6E0);
  static const danger = Color(0xFFE11D48);
  static const dangerSoft = Color(0xFFFDECEF);
  static const info = Color(0xFF4F46E5);
  static const infoSoft = Color(0xFFEEEDFD);
  static const love = Color(0xFFE8457A);
  static const loveSoft = Color(0xFFFDEBF1);

  static const primaryGradient = LinearGradient(
    colors: [Color(0xFFFF8A2B), primary],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const cosmicGradient = LinearGradient(
    colors: [Color(0xFF2B1E6E), cosmic, Color(0xFF110C30)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const loveGradient = LinearGradient(
    colors: [Color(0xFFFF7A9C), love],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

class AppSpacing {
  AppSpacing._();
  static const xxs = 4.0;
  static const xs = 8.0;
  static const sm = 12.0;
  static const md = 16.0;
  static const lg = 20.0;
  static const xl = 24.0;
  static const xxl = 32.0;

  /// Horizontal page gutter used by every screen.
  static const page = 16.0;
  static const pagePadding = EdgeInsets.symmetric(horizontal: page);
}

class AppRadius {
  AppRadius._();
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const pill = 999.0;

  static final card = BorderRadius.circular(lg);
  static final input = BorderRadius.circular(md);
  static final button = BorderRadius.circular(md);
  static const sheet = BorderRadius.vertical(top: Radius.circular(xl));
}

class AppShadows {
  AppShadows._();
  static final card = [
    BoxShadow(
      color: const Color(0xFF14142B).withValues(alpha: 0.05),
      blurRadius: 16,
      offset: const Offset(0, 4),
    ),
  ];
  static final raised = [
    BoxShadow(
      color: const Color(0xFF14142B).withValues(alpha: 0.10),
      blurRadius: 24,
      offset: const Offset(0, 8),
    ),
  ];
  static List<BoxShadow> glow(Color c) => [
        BoxShadow(color: c.withValues(alpha: 0.30), blurRadius: 18, offset: const Offset(0, 6)),
      ];
}

/// Type scale. Use `AppText.title` etc. or the matching `Theme.of(context)
/// .textTheme` entries (they are the same styles).
class AppText {
  AppText._();
  static const display = TextStyle(
      fontSize: 28, height: 1.2, fontWeight: FontWeight.w800, letterSpacing: -0.6, color: AppColors.textPrimary);
  static const headline = TextStyle(
      fontSize: 22, height: 1.25, fontWeight: FontWeight.w800, letterSpacing: -0.4, color: AppColors.textPrimary);
  static const title = TextStyle(
      fontSize: 18, height: 1.3, fontWeight: FontWeight.w700, letterSpacing: -0.2, color: AppColors.textPrimary);
  static const subtitle = TextStyle(
      fontSize: 15, height: 1.35, fontWeight: FontWeight.w600, color: AppColors.textPrimary);
  static const body = TextStyle(fontSize: 14, height: 1.45, fontWeight: FontWeight.w400, color: AppColors.textSecondary);
  static const bodyStrong =
      TextStyle(fontSize: 14, height: 1.45, fontWeight: FontWeight.w600, color: AppColors.textPrimary);
  static const caption = TextStyle(fontSize: 12, height: 1.35, fontWeight: FontWeight.w500, color: AppColors.textTertiary);
  static const overline = TextStyle(
      fontSize: 11, height: 1.3, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: AppColors.textTertiary);
  static const button = TextStyle(fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 0.1);
}

class AppTheme {
  AppTheme._();

  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      primary: AppColors.primary,
      onPrimary: Colors.white,
      secondary: AppColors.cosmic,
      onSecondary: Colors.white,
      surface: AppColors.surface,
      onSurface: AppColors.textPrimary,
      error: AppColors.danger,
    );

    final base = ThemeData(useMaterial3: true, colorScheme: scheme, fontFamily: 'Roboto');

    return base.copyWith(
      scaffoldBackgroundColor: AppColors.background,
      primaryColor: AppColors.primary,
      splashFactory: InkSparkle.splashFactory,
      textTheme: base.textTheme.copyWith(
        displaySmall: AppText.display,
        headlineSmall: AppText.headline,
        titleLarge: AppText.title,
        titleMedium: AppText.subtitle,
        bodyLarge: AppText.bodyStrong,
        bodyMedium: AppText.body,
        bodySmall: AppText.caption,
        labelLarge: AppText.button,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        shadowColor: AppColors.border,
        centerTitle: false,
        titleTextStyle: TextStyle(
            fontFamily: 'Roboto',
            fontSize: 18,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
            color: AppColors.textPrimary),
        systemOverlayStyle: SystemUiOverlayStyle.dark,
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.card,
          side: const BorderSide(color: AppColors.border),
        ),
      ),
      dividerTheme: const DividerThemeData(color: AppColors.divider, thickness: 1, space: 1),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.border,
          disabledForegroundColor: AppColors.textTertiary,
          elevation: 0,
          minimumSize: const Size(64, 50),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          textStyle: AppText.button,
          shape: RoundedRectangleBorder(borderRadius: AppRadius.button),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size(64, 50),
          textStyle: AppText.button,
          shape: RoundedRectangleBorder(borderRadius: AppRadius.button),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          minimumSize: const Size(64, 50),
          side: const BorderSide(color: AppColors.border, width: 1.2),
          textStyle: AppText.button,
          shape: RoundedRectangleBorder(borderRadius: AppRadius.button),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        hintStyle: const TextStyle(color: AppColors.textTertiary, fontSize: 14),
        labelStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
        floatingLabelStyle: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600),
        prefixIconColor: AppColors.textTertiary,
        border: OutlineInputBorder(borderRadius: AppRadius.input, borderSide: const BorderSide(color: AppColors.border)),
        enabledBorder:
            OutlineInputBorder(borderRadius: AppRadius.input, borderSide: const BorderSide(color: AppColors.border)),
        focusedBorder: OutlineInputBorder(
            borderRadius: AppRadius.input, borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
        errorBorder:
            OutlineInputBorder(borderRadius: AppRadius.input, borderSide: const BorderSide(color: AppColors.danger)),
        focusedErrorBorder: OutlineInputBorder(
            borderRadius: AppRadius.input, borderSide: const BorderSide(color: AppColors.danger, width: 1.5)),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: AppColors.surface,
        selectedColor: AppColors.primarySoft,
        side: const BorderSide(color: AppColors.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.pill)),
        labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
        checkmarkColor: AppColors.primary,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: AppColors.border,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.sheet),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.xl)),
        titleTextStyle: AppText.title,
        contentTextStyle: AppText.body,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.textPrimary,
        contentTextStyle: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
        actionTextColor: AppColors.gold,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: AppColors.primary,
        unselectedLabelColor: AppColors.textSecondary,
        indicatorColor: AppColors.primary,
        dividerColor: AppColors.divider,
        labelStyle: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        unselectedLabelStyle: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: AppColors.primary),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.white : null),
        trackColor:
            WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? AppColors.primary : null),
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: AppColors.textSecondary,
        titleTextStyle: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
        subtitleTextStyle: TextStyle(fontSize: 13, color: AppColors.textSecondary),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
      }),
    );
  }
}
