import 'package:flutter/material.dart';

class AppTheme {
  AppTheme._();

  static const petroleum = Color(0xFF12483D);
  static const ivory = Color(0xFFF6F3EB);
  static const mint = Color(0xFFEAF4F0);

  static final ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: ivory,
    colorScheme:
        ColorScheme.fromSeed(
          seedColor: petroleum,
          brightness: Brightness.light,
          surface: ivory,
        ).copyWith(
          primary: petroleum,
          onPrimary: Colors.white,
          secondary: const Color(0xFF3B806D),
          secondaryContainer: mint,
          onSecondaryContainer: petroleum,
          surface: ivory,
          onSurface: const Color(0xFF183B34),
          error: const Color(0xFFB7473D),
        ),
    appBarTheme: const AppBarTheme(
      backgroundColor: ivory,
      foregroundColor: petroleum,
      centerTitle: false,
      toolbarHeight: 68,
      titleSpacing: 20,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: TextStyle(
        color: petroleum,
        fontSize: 20,
        fontWeight: FontWeight.w700,
      ),
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 1.5,
      shadowColor: const Color(0x1814483D),
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFFF8F9F6),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFE1E7E1)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFE1E7E1)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: petroleum, width: 1.5),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: petroleum,
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: petroleum,
      foregroundColor: Colors.white,
      shape: StadiumBorder(),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: petroleum,
        minimumSize: const Size(0, 48),
        side: const BorderSide(color: Color(0xFFD8E9E2)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      indicatorColor: mint,
      elevation: 8,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return TextStyle(
          color: selected ? petroleum : const Color(0xFF87938E),
          fontSize: 11,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(
          color: selected ? petroleum : const Color(0xFF87938E),
        );
      }),
    ),
    navigationRailTheme: const NavigationRailThemeData(
      backgroundColor: Colors.white,
      selectedIconTheme: IconThemeData(color: petroleum),
      unselectedIconTheme: IconThemeData(color: Color(0xFF87938E)),
      indicatorColor: mint,
    ),
    listTileTheme: const ListTileThemeData(
      iconColor: petroleum,
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 3),
    ),
    dividerTheme: const DividerThemeData(
      color: Color(0xFFE5E9E4),
      thickness: 1,
      space: 1,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: petroleum,
    ),
  );
}
