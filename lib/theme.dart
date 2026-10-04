import 'package:flutter/material.dart';

abstract final class ConnectColors {
  static const ink = Color(0xFF07131C);
  static const deep = Color(0xFF0B2836);
  static const tile = Color(0xFF102C3C);
  static const line = Color(0xFF1C4A5C);
  static const cyan = Color(0xFF3EE7F5);
  static const text = Color(0xFFE7F7FB);
  static const muted = Color(0xFF8FB4C2);
  static const disc = Color(0xFF16344C);
  static const warn = Color(0xFFFFB089);
}

ThemeData connectTheme() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    fontFamily: 'Outfit',
    scaffoldBackgroundColor: ConnectColors.ink,
  );
  return base.copyWith(
    colorScheme: const ColorScheme.dark(
      surface: ConnectColors.ink,
      primary: ConnectColors.cyan,
      onPrimary: Color(0xFF042026),
      secondary: ConnectColors.cyan,
      onSurface: ConnectColors.text,
    ),
    textTheme: base.textTheme.apply(
      bodyColor: ConnectColors.text,
      displayColor: ConnectColors.text,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: ConnectColors.cyan,
        foregroundColor: const Color(0xFF042026),
        minimumSize: const Size.fromHeight(56),
        textStyle: const TextStyle(
          fontFamily: 'Outfit',
          fontWeight: FontWeight.w700,
          fontSize: 17,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
  );
}

const connectBackground = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [Color(0xFF07151F), ConnectColors.deep, ConnectColors.ink],
);
