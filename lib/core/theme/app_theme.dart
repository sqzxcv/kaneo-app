import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import 'tokens.dart';

export 'tokens.dart';

extension KaneoThemeContext on BuildContext {
  /// The web app's color tokens for the current brightness.
  KaneoColors get colors => Theme.of(this).extension<KaneoColors>()!;
}

const _themeModeKey = 'kaneo.themeMode';

/// Follows the system until the user picks a mode.
final themeModeProvider = NotifierProvider<ThemeModeController, ThemeMode>(ThemeModeController.new);

class ThemeModeController extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    final saved = ref.watch(prefsProvider).getString(_themeModeKey);
    return ThemeMode.values.asNameMap()[saved] ?? ThemeMode.system;
  }

  Future<void> select(ThemeMode mode) async {
    state = mode;
    await ref.read(prefsProvider).setString(_themeModeKey, mode.name);
  }
}

/// Text sizes from Tailwind's scale, with the web app's heading weight and tracking.
TextTheme _textTheme(Color foreground, Color muted) {
  TextStyle style(
    double size,
    double height,
    FontWeight weight, {
    double tracking = 0,
    Color? color,
  }) => TextStyle(
    fontFamily: KaneoFonts.sans,
    fontSize: size,
    height: height / size,
    fontWeight: weight,
    letterSpacing: tracking,
    color: color ?? foreground,
  );
  const regular = FontWeight.w400;
  const medium = FontWeight.w500;
  const semibold = FontWeight.w600;
  return TextTheme(
    displayLarge: style(36, 40, semibold, tracking: -0.9),
    displayMedium: style(30, 36, semibold, tracking: -0.75),
    displaySmall: style(24, 32, semibold, tracking: -0.6),
    headlineLarge: style(24, 32, semibold, tracking: -0.6),
    headlineMedium: style(20, 28, semibold, tracking: -0.5),
    headlineSmall: style(18, 28, semibold, tracking: -0.45),
    titleLarge: style(18, 28, semibold, tracking: -0.45),
    titleMedium: style(16, 24, semibold, tracking: -0.4),
    titleSmall: style(14, 20, semibold),
    bodyLarge: style(16, 24, regular),
    bodyMedium: style(14, 20, regular),
    bodySmall: style(12, 16, regular, color: muted),
    labelLarge: style(14, 20, medium),
    labelMedium: style(12, 16, medium),
    labelSmall: style(11, 16, medium, color: muted),
  );
}

ThemeData _theme(Brightness brightness, KaneoColors c) {
  final scheme = ColorScheme(
    brightness: brightness,
    primary: c.primary,
    onPrimary: c.primaryForeground,
    secondary: c.secondary,
    onSecondary: c.secondaryForeground,
    error: c.destructive,
    onError: const Color(0xFFFFFFFF),
    surface: c.background,
    onSurface: c.foreground,
    onSurfaceVariant: c.mutedForeground,
    surfaceContainerLowest: c.background,
    surfaceContainerLow: c.card,
    surfaceContainer: c.popover,
    surfaceContainerHigh: c.popover,
    surfaceContainerHighest: c.popover,
    outline: c.border,
    outlineVariant: c.border,
    surfaceTint: const Color(0x00000000),
  );
  final radius = BorderRadius.circular(KaneoRadius.md);
  final border = BorderSide(color: c.border);
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    fontFamily: KaneoFonts.sans,
    textTheme: _textTheme(c.foreground, c.mutedForeground),
    scaffoldBackgroundColor: c.background,
    canvasColor: c.background,
    dividerColor: c.border,
    extensions: [c],
    appBarTheme: AppBarTheme(
      backgroundColor: c.background,
      foregroundColor: c.foreground,
      elevation: 0,
      scrolledUnderElevation: 0,
      shape: Border(bottom: border),
      titleTextStyle: _textTheme(c.foreground, c.mutedForeground).titleSmall,
    ),
    cardTheme: CardThemeData(
      color: c.card,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(KaneoRadius.lg),
        side: border,
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: c.popover,
      surfaceTintColor: const Color(0x00000000),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(KaneoRadius.xl),
        side: border,
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.popover,
      surfaceTintColor: const Color(0x00000000),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(KaneoRadius.xl)),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: c.popover,
      surfaceTintColor: const Color(0x00000000),
      shape: RoundedRectangleBorder(borderRadius: radius, side: border),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: c.primary,
        foregroundColor: c.primaryForeground,
        shape: RoundedRectangleBorder(borderRadius: radius),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: c.foreground,
        side: border,
        shape: RoundedRectangleBorder(borderRadius: radius),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: c.foreground,
        shape: RoundedRectangleBorder(borderRadius: radius),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      border: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: c.input),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: c.input),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: c.ring),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: c.popover,
      contentTextStyle: TextStyle(
        fontFamily: KaneoFonts.sans,
        fontSize: 14,
        color: c.popoverForeground,
      ),
      behavior: SnackBarBehavior.floating,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: radius, side: border),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: c.background,
      surfaceTintColor: const Color(0x00000000),
      indicatorColor: c.accent,
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: c.sidebar,
      indicatorColor: c.sidebarAccent,
    ),
  );
}

final ThemeData kaneoLightTheme = _theme(Brightness.light, KaneoColors.light);
final ThemeData kaneoDarkTheme = _theme(Brightness.dark, KaneoColors.dark);
