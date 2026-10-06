import 'package:flutter/material.dart';

const cream = Color(0xFFFFF8F0);
const mint = Color(0xFFB8E0D2);
const lavender = Color(0xFFD6C8F0); // białko
const peach = Color(0xFFFFD6BA); // tłuszcze
const sky = Color(0xFFBFD7EA); // węglowodany
const rose = Color(0xFFF7C5CC); // akcent / przekroczenie normy
const ink = Color(0xFF3D3A4B);

final appTheme = ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(
    seedColor: mint,
    surface: cream,
    primary: const Color(0xFF5FA58F),
    secondary: const Color(0xFF9B87C9),
  ),
  scaffoldBackgroundColor: cream,
  appBarTheme: const AppBarTheme(backgroundColor: cream, centerTitle: true, foregroundColor: ink),
  cardTheme: CardTheme(
    color: Colors.white,
    elevation: 2,
    shadowColor: Colors.black12,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
  ),
  navigationBarTheme: const NavigationBarThemeData(backgroundColor: Colors.white, indicatorColor: mint),
  floatingActionButtonTheme: const FloatingActionButtonThemeData(backgroundColor: rose, foregroundColor: ink),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: const Color(0xFFF6F1FA), // widoczne i na kremowym tle, i na białych kartach
    hintStyle: const TextStyle(color: Colors.black38),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
  ),
);
