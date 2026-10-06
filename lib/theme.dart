import 'package:flutter/material.dart';

// Powierzchnie i tekst
const porcelain = Color(0xFFF6F5F9); // tło aplikacji
const ink = Color(0xFF2E2A38);
const inkMuted = Color(0xFF7A7488);
const line = Color(0xFFE7E3EE);
const track = Color(0xFFF0EDF5); // tło pasków postępu

// Akcent
const heather = Color(0xFF7C6AAE);
const heatherSoft = Color(0xFFECE7F6);

// Składniki: przygaszone pastele o zbliżonej jasności
const blush = Color(0xFFE7A6B4); // kalorie
const lilac = Color(0xFFB4A7DD); // białko
const clay = Color(0xFFE6B5A6); // tłuszcze
const powder = Color(0xFFA6C2E3); // węglowodany
const sage = Color(0xFF9EC6B6); // błonnik
const slate = Color(0xFFB9C1CF); // sól

// Przekroczenie limitu
const overBar = Color(0xFFD9899A);
const overText = Color(0xFFB4566B);

const _font = 'PlusJakartaSans';

final appTheme = () {
  final scheme = ColorScheme.fromSeed(seedColor: heather).copyWith(
    primary: heather,
    onPrimary: Colors.white,
    secondaryContainer: heatherSoft,
    onSecondaryContainer: ink,
    surface: Colors.white,
    onSurface: ink,
    onSurfaceVariant: inkMuted,
    outline: line,
    outlineVariant: line,
  );
  final base = ThemeData(useMaterial3: true, colorScheme: scheme, fontFamily: _font);
  final field = OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: line));
  return base.copyWith(
    scaffoldBackgroundColor: porcelain,
    textTheme: base.textTheme
        .copyWith(
          headlineMedium: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: -.6, height: 1.15),
          titleLarge: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -.3),
          titleMedium: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: -.1),
          titleSmall: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          bodyMedium: const TextStyle(fontSize: 14, height: 1.4),
          bodySmall: const TextStyle(fontSize: 12, height: 1.35, color: inkMuted),
          labelSmall: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: inkMuted),
        )
        .apply(fontFamily: _font, bodyColor: ink, displayColor: ink),
    appBarTheme: const AppBarTheme(
      backgroundColor: porcelain,
      surfaceTintColor: Colors.transparent,
      foregroundColor: ink,
      centerTitle: false,
      titleTextStyle: TextStyle(fontFamily: _font, fontSize: 18, fontWeight: FontWeight.w700, color: ink),
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      indicatorColor: heatherSoft,
      height: 68,
      labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
            fontFamily: _font,
            fontSize: 12,
            fontWeight: s.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.w500,
            color: s.contains(WidgetState.selected) ? ink : inkMuted,
          )),
      iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(color: s.contains(WidgetState.selected) ? heather : inkMuted)),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: heather,
      foregroundColor: Colors.white,
      elevation: 2,
      highlightElevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      extendedTextStyle: const TextStyle(fontFamily: _font, fontWeight: FontWeight.w600, fontSize: 15),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontFamily: _font, fontWeight: FontWeight.w600, fontSize: 15),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        foregroundColor: ink,
        side: const BorderSide(color: line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontFamily: _font, fontWeight: FontWeight.w600, fontSize: 14),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: heather,
        textStyle: const TextStyle(fontFamily: _font, fontWeight: FontWeight.w600),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        backgroundColor: Colors.white,
        selectedBackgroundColor: heatherSoft,
        selectedForegroundColor: ink,
        foregroundColor: inkMuted,
        side: const BorderSide(color: line),
        textStyle: const TextStyle(fontFamily: _font, fontWeight: FontWeight.w600),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: Colors.white,
      side: const BorderSide(color: line),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      labelStyle: const TextStyle(fontFamily: _font, fontWeight: FontWeight.w500, color: ink),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: field,
      enabledBorder: field,
      focusedBorder: field.copyWith(borderSide: const BorderSide(color: heather, width: 1.5)),
      labelStyle: const TextStyle(color: inkMuted),
      hintStyle: const TextStyle(color: Color(0xFFB0AABB)),
      helperStyle: const TextStyle(color: inkMuted, fontSize: 11),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    ),
    dividerTheme: const DividerThemeData(color: line, thickness: 1, space: 1),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: ink,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
  );
}();

/// Duży tytuł ekranu wyrównany do lewej, z opcjonalnym podtytułem.
class PageHeader extends StatelessWidget {
  const PageHeader(this.title, {super.key, this.subtitle, this.trailing, this.onTap});
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 12, 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(
          child: GestureDetector(
            onTap: onTap,
            behavior: HitTestBehavior.opaque,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: t.headlineMedium),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(subtitle!, style: t.bodyMedium?.copyWith(color: inkMuted)),
              ],
            ]),
          ),
        ),
        if (trailing != null) trailing!,
      ]),
    );
  }
}
