import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Tema oscuro tipo gimnasio: negro de fondo, naranja para lo accionable.
/// El naranja se reserva para acciones y datos en foco; el resto es gris.
const _orange = Color(0xFFFF7A18);
const _orangeDeep = Color(0xFFE85D04);
const _black = Color(0xFF0B0B0C);
const _surface = Color(0xFF141417);
const _surfaceHigh = Color(0xFF1D1D21);
const _outline = Color(0xFF3A3A40);

const appColors = ColorScheme(
  brightness: Brightness.dark,
  primary: _orange,
  onPrimary: Color(0xFF1A0C00),
  primaryContainer: _orangeDeep,
  onPrimaryContainer: Color(0xFFFFF2E6),
  secondary: Color(0xFFFFB067),
  onSecondary: Color(0xFF241100),
  secondaryContainer: Color(0xFF3A2410),
  onSecondaryContainer: Color(0xFFFFDDBF),
  tertiary: Color(0xFF7ED957),
  onTertiary: Color(0xFF0B1A05),
  error: Color(0xFFFF6B6B),
  onError: Color(0xFF2A0000),
  errorContainer: Color(0xFF4A1414),
  onErrorContainer: Color(0xFFFFDAD6),
  surface: _surface,
  onSurface: Color(0xFFF2F2F3),
  onSurfaceVariant: Color(0xFFB9B9C0),
  surfaceContainerHighest: _surfaceHigh,
  outline: _outline,
  outlineVariant: Color(0xFF2A2A30),
  shadow: Colors.black,
  scrim: Colors.black,
  inverseSurface: Color(0xFFE6E6E8),
  onInverseSurface: _black,
  inversePrimary: _orangeDeep,
);

ThemeData buildGymTheme() {
  final base = ThemeData(colorScheme: appColors, useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: _black,
    canvasColor: _black,
    appBarTheme: const AppBarTheme(
      backgroundColor: _black,
      surfaceTintColor: Colors.transparent,
      foregroundColor: Colors.white,
      centerTitle: false,
      titleTextStyle: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: 0.2),
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
    ),
    cardTheme: CardTheme(
      color: _surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFF232329)),
      ),
    ),
    dividerTheme: const DividerThemeData(color: Color(0xFF232329), space: 24),
    textTheme: base.textTheme.copyWith(
      titleMedium: base.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      titleSmall: base.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
      labelLarge: base.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: _orange,
        foregroundColor: const Color(0xFF1A0C00),
        minimumSize: const Size(0, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xFFF2F2F3),
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        side: const BorderSide(color: _outline),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: _orange)),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: _orange,
      foregroundColor: Color(0xFF1A0C00),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: const Color(0xFF101013),
      indicatorColor: _orange.withOpacity(0.18),
      elevation: 0,
      height: 68,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 11,
          fontWeight: states.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
          color: states.contains(WidgetState.selected) ? _orange : const Color(0xFF9A9AA2),
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected) ? _orange : const Color(0xFF9A9AA2),
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: _surfaceHigh,
      labelStyle: const TextStyle(color: Color(0xFFB9B9C0)),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _orange, width: 1.6),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: _surfaceHigh,
      selectedColor: _orange,
      side: const BorderSide(color: _outline),
      labelStyle: const TextStyle(color: Color(0xFFE6E6E8), fontWeight: FontWeight.w600),
      secondaryLabelStyle: const TextStyle(color: Color(0xFF1A0C00), fontWeight: FontWeight.w700),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? _orange : _surfaceHigh,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? const Color(0xFF1A0C00) : const Color(0xFFE6E6E8),
        ),
        side: WidgetStateProperty.all(const BorderSide(color: _outline)),
        textStyle: WidgetStateProperty.all(const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
      ),
    ),
    listTileTheme: const ListTileThemeData(iconColor: Color(0xFFB9B9C0)),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: _orange,
      linearTrackColor: Color(0xFF2A2A30),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: _surfaceHigh,
      contentTextStyle: TextStyle(color: Color(0xFFF2F2F3)),
      behavior: SnackBarBehavior.floating,
    ),
    dialogTheme: DialogTheme(
      backgroundColor: _surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(backgroundColor: _surface, surfaceTintColor: Colors.transparent),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? _orange : const Color(0xFF9A9AA2),
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? _orange.withOpacity(0.35) : const Color(0xFF2A2A30),
      ),
    ),
  );
}
