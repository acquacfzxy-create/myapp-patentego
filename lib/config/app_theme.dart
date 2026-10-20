import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

enum AppThemeMode { classic, night, retro }

class AppThemeModeCodec {
  const AppThemeModeCodec._();

  static String encode(AppThemeMode mode) {
    switch (mode) {
      case AppThemeMode.classic:
        return 'classic';
      case AppThemeMode.night:
        return 'dark';
      case AppThemeMode.retro:
        return 'retro';
    }
  }

  static AppThemeMode decode(String? value) {
    switch (value) {
      case 'dark':
        return AppThemeMode.night;
      case 'retro':
        return AppThemeMode.retro;
      case 'classic':
      default:
        return AppThemeMode.classic;
    }
  }
}

/// Marks theme variants that cannot be inferred from brightness alone.
///
/// The retro theme is intentionally light, so a ThemeExtension keeps it
/// distinct from the classic light theme.
class AppThemeVariant extends ThemeExtension<AppThemeVariant> {
  const AppThemeVariant({this.isRetro = false});

  const AppThemeVariant.retro() : isRetro = true;

  final bool isRetro;

  @override
  AppThemeVariant copyWith({bool? isRetro}) {
    return AppThemeVariant(isRetro: isRetro ?? this.isRetro);
  }

  @override
  AppThemeVariant lerp(covariant AppThemeVariant? other, double t) {
    if (other == null) return this;
    return t < 0.5 ? this : other;
  }
}

class AppTheme {
  const AppTheme._();

  static const Color primary = Color(0xFF2563EB);
  static const Color primaryDark = Color(0xFF1D4ED8);
  static const Color primarySoft = Color(0xFFEFF6FF);
  static const Color roadGreen = Color(0xFF16A34A);
  static const Color roadGreenSoft = Color(0xFFEAF7EF);
  static const Color roadGreenText = Color(0xFF15803D);
  static const Color warning = Color(0xFFF59E0B);
  static const Color warningText = Color(0xFFB45309);
  static const Color danger = Color(0xFFDC2626);
  static const Color ink = Color(0xFF111827);
  static const Color muted = Color(0xFF64748B);
  static const Color line = Color(0xFFE2E8F0);
  static const Color pageTop = Color(0xFFEAF4FF);
  static const Color pageMid = Color(0xFFF6FAFF);
  static const Color pageBottom = Color(0xFFFFFCF7);
  static const Color surface = Color(0xEFFFFFFF);
  static const Color nightPage = Color(0xFF0B1220);
  static const Color nightPageTop = Color(0xFF111C33);
  static const Color nightSurface = Color(0xFF172033);
  static const Color nightSurfaceAlt = Color(0xFF1E293B);
  static const Color nightPrimary = Color(0xFF60A5FA);
  static const Color nightPrimarySoft = Color(0xFF1E3A5F);
  static const Color nightInk = Color(0xFFF8FAFC);
  static const Color nightMuted = Color(0xFFA8B3C7);
  static const Color nightLine = Color(0xFF334155);
  static const Color retroPage = Color(0xFFD7E0B5);
  static const Color retroPageAlt = Color(0xFFC6D19F);
  static const Color retroSurface = Color(0xFFE4EBCB);
  static const Color retroSurfaceAlt = Color(0xFFBBC98F);
  static const Color retroPrimary = Color(0xFF263A24);
  static const Color retroInk = Color(0xFF1F331E);
  static const Color retroMuted = Color(0xFF59684B);
  static const Color retroLine = Color(0xFF59684B);
  static const Color retroDanger = Color(0xFF5A3018);
  static const String retroPixelFontFamily = 'FusionPixel';
  static const Color premiumNavy = Color(0xFF0F172A);
  static const Color premiumBlue = Color(0xFF1E3A8A);
  static const Color premiumGold = Color(0xFFFACC15);

  // 道路標誌主題（移動端經典／夜間）。上方舊藍色常量保留給 Web 端，
  // Web 介面暫不跟隨本輪改版。
  static const Color roadPrimary = Color(0xFF0A6B45);
  static const Color roadPrimaryDark = Color(0xFF06472E);
  static const Color roadPrimarySoft = Color(0xFFE3F1EA);
  static const Color roadAccent = Color(0xFFFFC20E);
  static const Color roadAccentSoft = Color(0xFFFFF3C4);
  static const Color roadAccentText = Color(0xFF7A5200);
  static const Color roadDanger = Color(0xFFC8102E);
  static const Color roadInk = Color(0xFF13201A);
  static const Color roadMuted = Color(0xFF5A635D);
  static const Color roadLine = Color(0xFFD6D2C7);
  static const Color roadPage = Color(0xFFF3F1EC);
  static const Color roadSurface = Color(0xFFFFFFFF);
  static const Color roadNightPage = Color(0xFF101512);
  static const Color roadNightSurface = Color(0xFF1A211D);
  static const Color roadNightSurfaceAlt = Color(0xFF232B26);
  static const Color roadNightPrimary = Color(0xFF4CC38A);
  static const Color roadNightPrimarySoft = Color(0xFF173A2A);
  static const Color roadNightInk = Color(0xFFF3F1EC);
  static const Color roadNightMuted = Color(0xFFA9B3AC);
  static const Color roadNightLine = Color(0xFF34403A);
  static const Color roadNightDanger = Color(0xFFFF6B7A);

  static const double radiusSm = 12;
  static const double radiusMd = 16;
  static const double radiusLg = 20;
  static const double radiusXl = 24;

  static String fontFamilyForLanguage(String language) {
    switch (language) {
      case 'ur':
        return 'NotoNastaliqUrdu';
      case 'pa':
        return 'NotoSansGurmukhi';
      case 'zh':
        return 'NotoSansSC';
      default:
        return 'NotoSans';
    }
  }

  static List<String> fontFallbackForLanguage(String language) {
    const families = [
      'NotoSans',
      'NotoSansSC',
      'NotoNastaliqUrdu',
      'NotoSansGurmukhi',
    ];
    final primaryFamily = fontFamilyForLanguage(language);
    return families.where((family) => family != primaryFamily).toList();
  }

  static List<String> retroFontFallbackForLanguage(String language) {
    return [
      fontFamilyForLanguage(language),
      ...fontFallbackForLanguage(language),
    ];
  }

  static const BoxDecoration pageDecoration = BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [pageTop, pageMid, pageBottom],
      stops: [0.0, 0.48, 1.0],
    ),
  );

  static const BoxDecoration retroPageDecoration = BoxDecoration(
    color: retroPage,
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [retroPage, retroPageAlt],
    ),
  );

  /// 移動端經典／夜間使用道路標誌配色；Web 端仍保持舊藍色主題。
  static bool get usesRoadPalette => !kIsWeb;

  static bool _isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  static BoxDecoration pageDecorationFor(BuildContext context) {
    if (isRetroFor(context)) {
      return retroPageDecoration;
    }
    if (usesRoadPalette) {
      return BoxDecoration(
        color: _isDark(context) ? roadNightPage : roadPage,
      );
    }
    if (_isDark(context)) {
      return const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [nightPageTop, nightPage],
        ),
      );
    }
    return pageDecoration;
  }

  static bool isRetroFor(BuildContext context) {
    return Theme.of(context).extension<AppThemeVariant>()?.isRetro == true;
  }

  static Color primaryFor(BuildContext context) {
    if (isRetroFor(context)) return retroPrimary;
    if (usesRoadPalette) {
      return _isDark(context) ? roadNightPrimary : roadPrimary;
    }
    return _isDark(context) ? nightPrimary : primary;
  }

  /// 二級頁頁面底色：道路主題與頁面同色，其餘沿用卡片表面色。
  static Color pageBackgroundFor(BuildContext context) {
    if (!isRetroFor(context) && usesRoadPalette) {
      return _isDark(context) ? roadNightPage : roadPage;
    }
    return Theme.of(context).colorScheme.surface;
  }

  /// 二級頁頂欄底色：道路主題為實色頁面底，不再用白色毛玻璃。
  static Color headerBackgroundFor(BuildContext context) {
    if (!isRetroFor(context) && usesRoadPalette) {
      return _isDark(context) ? roadNightPage : roadPage;
    }
    return Theme.of(context).colorScheme.surface.withOpacity(0.82);
  }

  /// 主行動按鈕用的標誌黃；復古主題沿用主色。
  static Color accentFor(BuildContext context) {
    if (isRetroFor(context)) return retroPrimary;
    if (usesRoadPalette) return roadAccent;
    return _isDark(context) ? nightPrimary : primary;
  }

  /// 標誌黃底上的文字／圖示顏色。
  static Color onAccentFor(BuildContext context) {
    if (isRetroFor(context)) return retroPage;
    if (usesRoadPalette) return roadInk;
    return _isDark(context) ? nightPage : Colors.white;
  }

  static Color inkFor(BuildContext context) {
    if (isRetroFor(context)) return retroInk;
    if (usesRoadPalette) return _isDark(context) ? roadNightInk : roadInk;
    return _isDark(context) ? nightInk : ink;
  }

  static Color mutedFor(BuildContext context) {
    if (isRetroFor(context)) return retroMuted;
    if (usesRoadPalette) return _isDark(context) ? roadNightMuted : roadMuted;
    return _isDark(context) ? nightMuted : muted;
  }

  static Color lineFor(BuildContext context) {
    if (isRetroFor(context)) return retroLine;
    if (usesRoadPalette) return _isDark(context) ? roadNightLine : roadLine;
    return _isDark(context) ? nightLine : line;
  }

  static Color primarySoftFor(BuildContext context) {
    if (isRetroFor(context)) return retroPageAlt;
    if (usesRoadPalette) {
      return _isDark(context) ? roadNightPrimarySoft : roadPrimarySoft;
    }
    return _isDark(context) ? nightPrimarySoft : primarySoft;
  }

  static Color surfaceFor(BuildContext context) {
    if (isRetroFor(context)) return retroSurface;
    if (usesRoadPalette) {
      return _isDark(context) ? roadNightSurface : roadSurface;
    }
    return _isDark(context) ? nightSurface : surface;
  }

  static Color successFor(BuildContext context) {
    if (isRetroFor(context)) return retroPrimary;
    if (usesRoadPalette) {
      return _isDark(context) ? roadNightPrimary : roadPrimary;
    }
    return _isDark(context) ? const Color(0xFF4ADE80) : roadGreen;
  }

  static Color successSoftFor(BuildContext context) {
    if (isRetroFor(context)) return retroPrimary.withOpacity(0.14);
    if (usesRoadPalette) {
      return _isDark(context) ? roadNightPrimarySoft : roadPrimarySoft;
    }
    return _isDark(context) ? const Color(0xFF14532D) : roadGreenSoft;
  }

  static Color warningFor(BuildContext context) {
    if (isRetroFor(context)) return retroPrimary;
    if (usesRoadPalette) return roadAccent;
    return _isDark(context) ? const Color(0xFFFBBF24) : warning;
  }

  static Color successTextFor(BuildContext context) {
    if (isRetroFor(context)) return retroPrimary;
    if (usesRoadPalette) {
      return _isDark(context) ? roadNightPrimary : roadPrimary;
    }
    return _isDark(context) ? const Color(0xFF4ADE80) : roadGreenText;
  }

  static Color warningTextFor(BuildContext context) {
    if (isRetroFor(context)) return retroPrimary;
    if (usesRoadPalette) return _isDark(context) ? roadAccent : roadAccentText;
    return _isDark(context) ? const Color(0xFFFBBF24) : warningText;
  }

  static Color dangerFor(BuildContext context) {
    if (isRetroFor(context)) return retroDanger;
    if (usesRoadPalette) return _isDark(context) ? roadNightDanger : roadDanger;
    return _isDark(context) ? const Color(0xFFF87171) : danger;
  }

  static Color dangerSoftFor(BuildContext context) {
    final color = dangerFor(context);
    return color.withOpacity(
      isRetroFor(context) ? 0.14 : 0.12,
    );
  }

  static const BoxDecoration premiumDecoration = BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [premiumNavy, premiumBlue, Color(0xFF0B1220)],
      stops: [0.0, 0.52, 1.0],
    ),
  );

  static List<BoxShadow> get cardShadow => [
        BoxShadow(
          color: primaryDark.withOpacity(0.07),
          blurRadius: 24,
          offset: const Offset(0, 12),
        ),
        BoxShadow(
          color: Colors.white.withOpacity(0.55),
          blurRadius: 0,
          spreadRadius: 1,
        ),
      ];

  static List<BoxShadow> cardShadowFor(BuildContext context) {
    if (isRetroFor(context)) return const [];
    if (usesRoadPalette) {
      // 厚底實色陰影，不模糊：卡片看起來「可按」，也比玻璃風更省繪製。
      return [
        BoxShadow(
          color: lineFor(context),
          blurRadius: 0,
          offset: const Offset(0, 3),
        ),
      ];
    }
    if (_isDark(context)) {
      return [
        BoxShadow(
          color: Colors.black.withOpacity(0.22),
          blurRadius: 18,
          offset: const Offset(0, 8),
        ),
      ];
    }
    return cardShadow;
  }

  /// 主行動按鈕與答題按鈕的厚底陰影；[pressed] 時收起，配合下沉位移。
  static List<BoxShadow> chunkyShadowFor(
    BuildContext context, {
    Color? color,
    bool pressed = false,
  }) {
    if (isRetroFor(context) || pressed) return const [];
    return [
      BoxShadow(
        color: color ??
            (_isDark(context) ? Colors.black.withOpacity(0.55) : roadInk),
        blurRadius: 0,
        offset: const Offset(0, 4),
      ),
    ];
  }

  static ThemeData retroTheme({String language = 'zh'}) {
    const fontFamily = retroPixelFontFamily;
    final fontFallback = retroFontFallbackForLanguage(language);
    final materialTheme = ThemeData(useMaterial3: true);
    final textTheme = materialTheme.textTheme.apply(
      fontFamily: fontFamily,
      fontFamilyFallback: fontFallback,
      bodyColor: retroInk,
      displayColor: retroInk,
    );
    final primaryTextTheme = materialTheme.primaryTextTheme.apply(
      fontFamily: fontFamily,
      fontFamilyFallback: fontFallback,
    );
    final scheme = ColorScheme.fromSeed(
      seedColor: retroPrimary,
      brightness: Brightness.light,
      primary: retroPrimary,
      secondary: retroPrimary,
      error: retroDanger,
      surface: retroSurface,
      background: retroPage,
    ).copyWith(
      onPrimary: retroPage,
      onSecondary: retroPage,
      onSurface: retroInk,
      onSurfaceVariant: retroMuted,
      surfaceVariant: retroSurfaceAlt,
      outline: retroLine,
      outlineVariant: retroLine.withOpacity(0.62),
      onBackground: retroInk,
      onError: retroPage,
    );

    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      scaffoldBackgroundColor: retroPage,
      fontFamily: fontFamily,
      fontFamilyFallback: fontFallback,
      textTheme: textTheme,
      primaryTextTheme: primaryTextTheme,
      extensions: const [AppThemeVariant.retro()],
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: retroInk,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontFamily: fontFamily,
          fontFamilyFallback: fontFallback,
          color: retroInk,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: CardThemeData(
        color: retroSurface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(2),
          side: const BorderSide(color: retroLine),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: retroLine,
        thickness: 1,
        space: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: retroPrimary,
        contentTextStyle: TextStyle(
          fontFamily: fontFamily,
          fontFamilyFallback: fontFallback,
          color: retroPage,
        ),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.zero,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: retroSurface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.zero,
          side: BorderSide(color: retroLine),
        ),
        titleTextStyle: TextStyle(
          fontFamily: fontFamily,
          fontFamilyFallback: fontFallback,
          color: retroInk,
          fontSize: 20,
          fontWeight: FontWeight.w800,
        ),
        contentTextStyle: TextStyle(
          fontFamily: fontFamily,
          fontFamilyFallback: fontFallback,
          color: retroMuted,
          fontSize: 15,
          height: 1.45,
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: retroSurface,
        modalBackgroundColor: retroSurface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.zero,
          side: BorderSide(color: retroLine),
        ),
        showDragHandle: false,
      ),
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        fillColor: retroSurface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: retroLine),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: retroLine),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: retroPrimary, width: 2),
        ),
      ),
      chipTheme: const ChipThemeData(
        backgroundColor: retroSurface,
        selectedColor: retroSurfaceAlt,
        disabledColor: retroSurface,
        side: BorderSide(color: retroLine),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        labelStyle: TextStyle(color: retroInk),
        secondaryLabelStyle: TextStyle(color: retroInk),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? retroPrimary
              : retroMuted;
        }),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? retroPrimary
              : Colors.transparent;
        }),
        checkColor: const WidgetStatePropertyAll(retroPage),
        side: const BorderSide(color: retroLine),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: retroPrimary,
          foregroundColor: retroPage,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.zero,
          ),
          textStyle: TextStyle(
            fontFamily: fontFamily,
            fontFamilyFallback: fontFallback,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: retroPrimary,
          foregroundColor: retroPage,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.zero,
          ),
          textStyle: TextStyle(
            fontFamily: fontFamily,
            fontFamilyFallback: fontFallback,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: retroPrimary,
          textStyle: TextStyle(
            fontFamily: fontFamily,
            fontFamilyFallback: fontFallback,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: retroPrimary,
      ),
      iconTheme: const IconThemeData(color: retroInk),
    );
  }

  static ThemeData lightTheme({String language = 'zh'}) {
    final fontFamily = fontFamilyForLanguage(language);
    final fontFallback = fontFallbackForLanguage(language);
    final materialTheme = ThemeData(useMaterial3: true);
    final textTheme = materialTheme.textTheme.apply(
      fontFamily: fontFamily,
      fontFamilyFallback: fontFallback,
      bodyColor: roadInk,
      displayColor: roadInk,
    );
    final primaryTextTheme = materialTheme.primaryTextTheme.apply(
      fontFamily: fontFamily,
      fontFamilyFallback: fontFallback,
    );
    final scheme = ColorScheme.fromSeed(
      seedColor: roadPrimary,
      primary: roadPrimary,
      secondary: roadPrimaryDark,
      error: roadDanger,
      surface: Colors.white,
      background: roadPage,
    );

    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      scaffoldBackgroundColor: roadPage,
      fontFamily: fontFamily,
      fontFamilyFallback: fontFallback,
      textTheme: textTheme,
      primaryTextTheme: primaryTextTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: roadInk,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontFamily: fontFamily,
          fontFamilyFallback: fontFallback,
          color: roadInk,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: CardThemeData(
        color: roadSurface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLg),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusSm),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLg),
        ),
        titleTextStyle: TextStyle(
          fontFamily: fontFamily,
          fontFamilyFallback: fontFallback,
          color: roadInk,
          fontSize: 20,
          fontWeight: FontWeight.w800,
        ),
        contentTextStyle: TextStyle(
          fontFamily: fontFamily,
          fontFamilyFallback: fontFallback,
          color: roadMuted,
          fontSize: 15,
          height: 1.45,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: Colors.white,
        modalBackgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(radiusXl),
          ),
        ),
        dragHandleColor: roadLine,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white.withOpacity(0.82),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: roadLine),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: roadLine),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: roadPrimary, width: 2),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: Colors.white.withOpacity(0.82),
        selectedColor: roadPrimarySoft,
        disabledColor: roadLine.withOpacity(0.5),
        side: const BorderSide(color: roadLine),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusSm),
        ),
        labelStyle: const TextStyle(color: roadInk),
        secondaryLabelStyle: const TextStyle(color: roadInk),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? roadPrimary
              : roadMuted;
        }),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? roadPrimary
              : Colors.transparent;
        }),
        checkColor: const WidgetStatePropertyAll(Colors.white),
        side: const BorderSide(color: roadMuted),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: roadPrimary,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd),
          ),
          textStyle: TextStyle(
            fontFamily: fontFamily,
            fontFamilyFallback: fontFallback,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: roadPrimary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd),
          ),
          textStyle: TextStyle(
            fontFamily: fontFamily,
            fontFamilyFallback: fontFallback,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: roadPrimary,
          textStyle: TextStyle(
            fontFamily: fontFamily,
            fontFamilyFallback: fontFallback,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: roadPrimary,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected) ? roadPrimary : null;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? roadPrimary.withOpacity(0.28)
              : null;
        }),
      ),
    );
  }

  static ThemeData darkTheme({String language = 'zh'}) {
    final fontFamily = fontFamilyForLanguage(language);
    final fontFallback = fontFallbackForLanguage(language);
    final materialTheme = ThemeData.dark(useMaterial3: true);
    final textTheme = materialTheme.textTheme.apply(
      fontFamily: fontFamily,
      fontFamilyFallback: fontFallback,
      bodyColor: roadNightInk,
      displayColor: roadNightInk,
    );
    final primaryTextTheme = materialTheme.primaryTextTheme.apply(
      fontFamily: fontFamily,
      fontFamilyFallback: fontFallback,
    );
    final scheme = ColorScheme.fromSeed(
      seedColor: roadNightPrimary,
      brightness: Brightness.dark,
      primary: roadNightPrimary,
      secondary: roadAccent,
      error: roadNightDanger,
      surface: roadNightSurface,
      background: roadNightPage,
    );

    return ThemeData(
      colorScheme: scheme,
      brightness: Brightness.dark,
      useMaterial3: true,
      scaffoldBackgroundColor: roadNightPage,
      fontFamily: fontFamily,
      fontFamilyFallback: fontFallback,
      textTheme: textTheme,
      primaryTextTheme: primaryTextTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: roadNightInk,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontFamily: fontFamily,
          fontFamilyFallback: fontFallback,
          color: roadNightInk,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: CardThemeData(
        color: roadNightSurface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLg),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: roadNightSurfaceAlt,
        contentTextStyle: TextStyle(
          fontFamily: fontFamily,
          fontFamilyFallback: fontFallback,
          color: roadNightInk,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusSm),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: roadNightSurface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLg),
        ),
        titleTextStyle: TextStyle(
          fontFamily: fontFamily,
          fontFamilyFallback: fontFallback,
          color: roadNightInk,
          fontSize: 20,
          fontWeight: FontWeight.w800,
        ),
        contentTextStyle: TextStyle(
          fontFamily: fontFamily,
          fontFamilyFallback: fontFallback,
          color: roadNightMuted,
          fontSize: 15,
          height: 1.45,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: roadNightSurface,
        modalBackgroundColor: roadNightSurface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(radiusXl),
          ),
        ),
        dragHandleColor: roadNightLine,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: roadNightSurfaceAlt,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: roadNightLine),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: roadNightLine),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: roadNightPrimary, width: 2),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: roadNightSurfaceAlt,
        selectedColor: roadNightPrimarySoft,
        disabledColor: roadNightLine.withOpacity(0.5),
        side: const BorderSide(color: roadNightLine),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusSm),
        ),
        labelStyle: const TextStyle(color: roadNightInk),
        secondaryLabelStyle: const TextStyle(color: roadNightInk),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? roadNightPrimary
              : roadNightMuted;
        }),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? roadNightPrimary
              : Colors.transparent;
        }),
        checkColor: const WidgetStatePropertyAll(roadNightPage),
        side: const BorderSide(color: roadNightMuted),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: roadNightPrimary,
          foregroundColor: roadNightPage,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd),
          ),
          textStyle: TextStyle(
            fontFamily: fontFamily,
            fontFamilyFallback: fontFallback,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: roadNightPrimary,
          foregroundColor: roadNightPage,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd),
          ),
          textStyle: TextStyle(
            fontFamily: fontFamily,
            fontFamilyFallback: fontFallback,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: roadNightPrimary,
          textStyle: TextStyle(
            fontFamily: fontFamily,
            fontFamilyFallback: fontFallback,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: roadNightPrimary,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? roadNightPrimary
              : null;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? roadNightPrimary.withOpacity(0.35)
              : null;
        }),
      ),
    );
  }

  /// Web uses the browser's system font stack so the first visit does not
  /// download the 50+ MB mobile CJK font bundle before practice can begin.
  static ThemeData webTheme({bool dark = false}) {
    if (dark) {
      return ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: nightPrimary,
          brightness: Brightness.dark,
          primary: nightPrimary,
          secondary: const Color(0xFF4ADE80),
          error: const Color(0xFFF87171),
          surface: nightSurface,
          background: nightPage,
        ),
        brightness: Brightness.dark,
        useMaterial3: true,
        scaffoldBackgroundColor: nightPage,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          foregroundColor: nightInk,
          elevation: 0,
          centerTitle: true,
        ),
        cardTheme: CardThemeData(
          color: nightSurface,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusLg),
          ),
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: nightSurface,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusLg),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: nightPrimary,
            foregroundColor: nightPage,
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(foregroundColor: nightPrimary),
        ),
        progressIndicatorTheme:
            const ProgressIndicatorThemeData(color: nightPrimary),
      );
    }
    final scheme = ColorScheme.fromSeed(
      seedColor: primary,
      primary: primary,
      secondary: roadGreen,
      error: danger,
      surface: Colors.white,
      background: pageMid,
    );

    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      scaffoldBackgroundColor: pageMid,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: ink,
        elevation: 0,
        centerTitle: true,
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLg),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusSm),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLg),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: primary),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: primary),
    );
  }
}
