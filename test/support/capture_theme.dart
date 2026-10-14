import 'package:flutter/material.dart';

/// Fuentes reales SOLO en capturas: los TextStyle explícitos sin familia
/// resuelven Ahem dentro de flutter_test. Conserva pesos, tamaños y geometría.
ThemeData captureTheme(ThemeData theme) {
  ButtonStyle withFont(ButtonStyle? style) =>
      (style ?? const ButtonStyle()).copyWith(
          textStyle: WidgetStateProperty.resolveWith((states) =>
              (style?.textStyle?.resolve(states) ??
                      theme.textTheme.labelLarge ??
                      const TextStyle())
                  .copyWith(fontFamily: 'Roboto')));
  return theme.copyWith(
    textTheme: theme.textTheme.apply(fontFamily: 'Roboto'),
    appBarTheme: theme.appBarTheme.copyWith(
        titleTextStyle:
            theme.appBarTheme.titleTextStyle?.copyWith(fontFamily: 'Roboto')),
    filledButtonTheme:
        FilledButtonThemeData(style: withFont(theme.filledButtonTheme.style)),
    outlinedButtonTheme: OutlinedButtonThemeData(
        style: withFont(theme.outlinedButtonTheme.style)),
    textButtonTheme:
        TextButtonThemeData(style: withFont(theme.textButtonTheme.style)),
    elevatedButtonTheme: ElevatedButtonThemeData(
        style: withFont(theme.elevatedButtonTheme.style)),
    chipTheme: theme.chipTheme.copyWith(
        labelStyle: theme.chipTheme.labelStyle?.copyWith(fontFamily: 'Roboto'),
        secondaryLabelStyle: theme.chipTheme.secondaryLabelStyle
            ?.copyWith(fontFamily: 'Roboto')),
  );
}
