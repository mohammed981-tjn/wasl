import 'package:flutter/material.dart';
import 'app_colors.dart';

/// اسم الخطّ العربيّ المضمَّن.
///
/// **مصيدةٌ تستحقّ التصريح**: `ThemeData.fontFamily` يسري على `textTheme`
/// **ولا يسري على `TextStyle` تُمرَّر لثيم مكوّن** (زرّ، شريط، رقاقة). فتلك
/// تعود إلى خطّ Flutter الافتراضي — وهو بلا حرفٍ عربيّ، فيظهر نصّ الزرّ
/// مربّعاتٍ فارغة بينما بقيّة الشاشة سليمة.
///
/// ولذلك يُذكر الخطّ في **كل** `TextStyle` هنا صراحةً. ومن يضيف نمطًا جديدًا
/// بلا `fontFamily: kFontFamily` سيرى المربّعات بنفسه.
const String kFontFamily = 'Cairo';

/// WASL Theme (clean & premium)
/// - Light: soft backgrounds, green primary, gold accents.
/// - Dark: deep surfaces, readable text, same brand colors.
class AppTheme {
  static ThemeData light() {
    const colorScheme = ColorScheme(
      brightness: Brightness.light,
      primary: AppColors.primary,
      onPrimary: Colors.white,
      secondary: AppColors.accent,
      onSecondary: Colors.black,
      error: AppColors.error,
      onError: Colors.white,
      surface: Colors.white,
      onSurface: AppColors.textPrimary,
    );

    return ThemeData(
      useMaterial3: true,
      // بلا هذا يرسم Flutter كل نصّ عربيّ مربّعاتٍ فارغة: خطّه الافتراضي
      // (Roboto) لا يحوي حرفًا عربيًّا، ولا «خطّ نظام» على الويب يُتّكل عليه.
      fontFamily: 'Cairo',
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.backgroundLight,
      dividerColor: AppColors.border,
      splashColor: colorScheme.primary.withValues(alpha: 0.08),
      highlightColor: colorScheme.primary.withValues(alpha: 0.06),

      // App bars
      appBarTheme: AppBarTheme(
        elevation: 0,
        centerTitle: true,
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: const TextStyle(fontFamily: kFontFamily, 
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),

      // شريطُ التبويب داخل شريط العنوان
      //
      // **بلا هذا يختفي عنوانُ التبويب المختار.** Material 3 يلوّن المختار
      // بـ`colorScheme.primary`، وشريطُ العنوان عندنا **بلون primary نفسه**
      // — فيصير أخضرَ على أخضر. وغيرُ المختار يبقى ظاهرًا (لونٌ آخر)، فيبدو
      // العطلُ «تبويبًا بلا اسم» لا خطأَ لون، ولا يُشكّ في السبب.
      tabBarTheme: TabBarThemeData(
        labelColor: colorScheme.onPrimary,
        unselectedLabelColor: colorScheme.onPrimary.withValues(alpha: 0.70),
        indicatorColor: colorScheme.onPrimary,
        dividerColor: Colors.transparent,
      ),

      // Cards / surfaces
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.border),
        ),
      ),

      // Buttons
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontFamily: kFontFamily, fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontFamily: kFontFamily, fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colorScheme.primary,
          side: const BorderSide(color: AppColors.border),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontFamily: kFontFamily, fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ),

      // Inputs
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceAlt,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: colorScheme.primary, width: 1.4),
        ),
        hintStyle: const TextStyle(fontFamily: kFontFamily, color: AppColors.textSecondary),
        labelStyle: const TextStyle(fontFamily: kFontFamily, color: AppColors.textSecondary),
      ),

      // Bottom nav
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: Colors.white,
        selectedItemColor: colorScheme.primary,
        unselectedItemColor: AppColors.textSecondary,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),

      // Chips
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surfaceAlt,
        selectedColor: colorScheme.primary.withValues(alpha: 0.12),
        labelStyle: const TextStyle(fontFamily: kFontFamily, fontWeight: FontWeight.w600),
        secondaryLabelStyle: const TextStyle(fontFamily: kFontFamily, fontWeight: FontWeight.w600),
        side: const BorderSide(color: AppColors.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),

      // Typography
      textTheme: const TextTheme(
        headlineSmall: TextStyle(fontFamily: kFontFamily, fontWeight: FontWeight.w800),
        titleLarge: TextStyle(fontFamily: kFontFamily, fontWeight: FontWeight.w800),
        titleMedium: TextStyle(fontFamily: kFontFamily, fontWeight: FontWeight.w700),
        bodyLarge: TextStyle(fontFamily: kFontFamily, fontWeight: FontWeight.w500),
        bodyMedium: TextStyle(fontFamily: kFontFamily, fontWeight: FontWeight.w500),
      ),
    );
  }

  static ThemeData dark() {
    const colorScheme = ColorScheme(
      brightness: Brightness.dark,
      primary: AppColors.primary,
      onPrimary: Colors.white,
      secondary: AppColors.accent,
      onSecondary: Colors.black,
      error: AppColors.error,
      onError: Colors.white,
      surface: AppColors.surfaceDark,
      onSurface: Colors.white,
    );

    return ThemeData(
      useMaterial3: true,
      // بلا هذا يرسم Flutter كل نصّ عربيّ مربّعاتٍ فارغة: خطّه الافتراضي
      // (Roboto) لا يحوي حرفًا عربيًّا، ولا «خطّ نظام» على الويب يُتّكل عليه.
      fontFamily: 'Cairo',
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.backgroundDark,
      dividerColor: AppColors.borderDark,
      splashColor: colorScheme.primary.withValues(alpha: 0.10),
      highlightColor: colorScheme.primary.withValues(alpha: 0.08),

      appBarTheme: const AppBarTheme(
        elevation: 0,
        centerTitle: true,
        backgroundColor: AppColors.surfaceDark,
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(fontFamily: kFontFamily, 
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
        iconTheme: IconThemeData(color: Colors.white),
      ),

      tabBarTheme: TabBarThemeData(
        labelColor: Colors.white,
        unselectedLabelColor: Colors.white.withValues(alpha: 0.70),
        indicatorColor: Colors.white,
        dividerColor: Colors.transparent,
      ),

      cardTheme: CardThemeData(
        color: AppColors.surfaceDark2,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.borderDark),
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontFamily: kFontFamily, fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceDark2,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.borderDark),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.borderDark),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: colorScheme.primary, width: 1.4),
        ),
        hintStyle: const TextStyle(fontFamily: kFontFamily, color: Colors.white70),
        labelStyle: const TextStyle(fontFamily: kFontFamily, color: Colors.white70),
      ),

      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: AppColors.surfaceDark,
        selectedItemColor: colorScheme.primary,
        unselectedItemColor: Colors.white60,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
    );
  }
}
