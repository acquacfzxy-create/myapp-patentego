import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lingua_patente/config/app_theme.dart';

void main() {
  test('selects the bundled font family for each writing system', () {
    expect(AppTheme.fontFamilyForLanguage('zh'), 'NotoSansSC');
    expect(AppTheme.fontFamilyForLanguage('en'), 'NotoSans');
    expect(AppTheme.fontFamilyForLanguage('ru'), 'NotoSans');
    expect(AppTheme.fontFamilyForLanguage('ur'), 'NotoNastaliqUrdu');
    expect(AppTheme.fontFamilyForLanguage('pa'), 'NotoSansGurmukhi');
  });

  test('component themes use the same family as body text', () {
    final theme = AppTheme.lightTheme(language: 'zh');
    final bodyFamily = theme.textTheme.bodyMedium?.fontFamily;

    expect(bodyFamily, 'NotoSansSC');
    expect(theme.appBarTheme.titleTextStyle?.fontFamily, bodyFamily);
    expect(theme.dialogTheme.titleTextStyle?.fontFamily, bodyFamily);
    expect(theme.dialogTheme.contentTextStyle?.fontFamily, bodyFamily);
    expect(
      theme.elevatedButtonTheme.style?.textStyle?.resolve({})?.fontFamily,
      bodyFamily,
    );
    expect(
      theme.filledButtonTheme.style?.textStyle?.resolve({})?.fontFamily,
      bodyFamily,
    );
    expect(
      theme.textButtonTheme.style?.textStyle?.resolve({})?.fontFamily,
      bodyFamily,
    );
  });

  test('dark theme keeps the night palette and bundled font family', () {
    final theme = AppTheme.darkTheme(language: 'zh');

    expect(theme.brightness, Brightness.dark);
    expect(theme.scaffoldBackgroundColor, AppTheme.nightPage);
    expect(theme.cardTheme.color, AppTheme.nightSurface);
    expect(theme.textTheme.bodyMedium?.fontFamily, 'NotoSansSC');
  });

  test('retro preview uses the green-screen palette and marker', () {
    final theme = AppTheme.retroTheme(language: 'zh');

    expect(theme.brightness, Brightness.light);
    expect(theme.scaffoldBackgroundColor, AppTheme.retroPage);
    expect(theme.cardTheme.color, AppTheme.retroSurface);
    expect(theme.textTheme.bodyMedium?.fontFamily, 'FusionPixel');
    expect(theme.extension<AppThemeVariant>()?.isRetro, isTrue);
  });

  test('retro component themes keep the electronic dictionary geometry', () {
    final theme = AppTheme.retroTheme(language: 'zh');
    final sheetShape = theme.bottomSheetTheme.shape as RoundedRectangleBorder;
    final inputBorder =
        theme.inputDecorationTheme.enabledBorder as OutlineInputBorder;
    final chipShape = theme.chipTheme.shape as RoundedRectangleBorder;

    expect(theme.bottomSheetTheme.modalBackgroundColor, AppTheme.retroSurface);
    expect(sheetShape.borderRadius, BorderRadius.zero);
    expect(inputBorder.borderRadius, BorderRadius.zero);
    expect(chipShape.borderRadius, BorderRadius.zero);
    expect(theme.bottomSheetTheme.showDragHandle, isFalse);
  });

  test('night component surfaces stay inside the night palette', () {
    final theme = AppTheme.darkTheme(language: 'zh');

    expect(theme.bottomSheetTheme.modalBackgroundColor, AppTheme.nightSurface);
    expect(theme.inputDecorationTheme.fillColor, AppTheme.nightSurfaceAlt);
    expect(theme.chipTheme.backgroundColor, AppTheme.nightSurfaceAlt);
    expect(theme.colorScheme.primary, AppTheme.nightPrimary);
  });

  testWidgets('semantic status colors adapt to every app theme',
      (tester) async {
    Future<List<Color>> resolveColors(ThemeData theme) async {
      late List<Color> colors;
      await tester.pumpWidget(
        MaterialApp(
          key: UniqueKey(),
          theme: theme,
          home: Builder(
            builder: (context) {
              colors = [
                AppTheme.primaryFor(context),
                AppTheme.successTextFor(context),
                AppTheme.warningTextFor(context),
                AppTheme.dangerFor(context),
              ];
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      return colors;
    }

    expect(
      await resolveColors(AppTheme.lightTheme(language: 'zh')),
      [
        AppTheme.primary,
        AppTheme.roadGreenText,
        AppTheme.warningText,
        AppTheme.danger,
      ],
    );
    expect(
      await resolveColors(AppTheme.darkTheme(language: 'zh')),
      const [
        AppTheme.nightPrimary,
        Color(0xFF4ADE80),
        Color(0xFFFBBF24),
        Color(0xFFF87171),
      ],
    );
    expect(
      await resolveColors(AppTheme.retroTheme(language: 'zh')),
      const [
        AppTheme.retroPrimary,
        AppTheme.retroPrimary,
        AppTheme.retroPrimary,
        AppTheme.retroDanger,
      ],
    );
  });

  test('theme mode storage keeps classic and night compatibility', () {
    expect(AppThemeModeCodec.decode('classic'), AppThemeMode.classic);
    expect(AppThemeModeCodec.decode('dark'), AppThemeMode.night);
    expect(AppThemeModeCodec.decode('retro'), AppThemeMode.retro);
    expect(AppThemeModeCodec.encode(AppThemeMode.retro), 'retro');
  });

  test('font fallbacks exclude the active primary family', () {
    final fallbacks = AppTheme.fontFallbackForLanguage('ur');

    expect(fallbacks, isNot(contains('NotoNastaliqUrdu')));
    expect(fallbacks, containsAll(['NotoSans', 'NotoSansSC']));
  });

  test('every Material text style explicitly uses the active bundled family',
      () {
    final theme = AppTheme.lightTheme(language: 'zh');
    final styles = [
      theme.textTheme.displayLarge,
      theme.textTheme.displayMedium,
      theme.textTheme.displaySmall,
      theme.textTheme.headlineLarge,
      theme.textTheme.headlineMedium,
      theme.textTheme.headlineSmall,
      theme.textTheme.titleLarge,
      theme.textTheme.titleMedium,
      theme.textTheme.titleSmall,
      theme.textTheme.bodyLarge,
      theme.textTheme.bodyMedium,
      theme.textTheme.bodySmall,
      theme.textTheme.labelLarge,
      theme.textTheme.labelMedium,
      theme.textTheme.labelSmall,
    ];

    for (final style in styles) {
      expect(style?.fontFamily, 'NotoSansSC');
      expect(style?.fontFamilyFallback, contains('NotoSans'));
    }
  });

  test('UI source cannot bypass the app font with raw RichText or literals',
      () {
    final dartFiles = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));

    for (final file in dartFiles) {
      final source = file.readAsStringSync();
      expect(
        source,
        isNot(contains('RichText(')),
        reason:
            '${file.path} must use Text.rich so DefaultTextStyle is inherited',
      );
      if (!file.path.endsWith('config/app_theme.dart')) {
        expect(
          RegExp(r'''fontFamily\s*:\s*['\"]''').hasMatch(source),
          isFalse,
          reason: '${file.path} must inherit the centralized AppTheme font',
        );
      }
    }
  });

  test('shipped web pages use an explicit sans-serif Chinese stack', () {
    for (final path in const [
      'docs/index.html',
      'docs/privacy.html',
      'docs/support.html',
      'docs/terms.html',
    ]) {
      final source = File(path).readAsStringSync();
      expect(source, contains('"Noto Sans SC"'));
      expect(source.replaceAll('sans-serif', ''), isNot(contains('serif')));
    }
  });
}
