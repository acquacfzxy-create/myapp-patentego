import 'package:flutter/material.dart';

import '../config/app_strings.dart';
import '../config/app_theme.dart';
import '../config/content_direction.dart';
import '../models/user_state.dart';

class TranslationPanel extends StatelessWidget {
  const TranslationPanel({
    super.key,
    required this.text,
    required this.languageCode,
  });

  final String text;
  final String languageCode;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isRetro = AppTheme.isRetroFor(context);
    final primaryColor = AppTheme.primaryFor(context);
    final inkColor = AppTheme.inkFor(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isRetro
            ? AppTheme.retroPageAlt
            : AppTheme.usesRoadPalette
                ? AppTheme.primarySoftFor(context)
                : isDark
                    ? AppTheme.nightPrimarySoft.withOpacity(0.92)
                    : AppTheme.primarySoft.withOpacity(0.78),
        borderRadius: isRetro
            ? BorderRadius.zero
            : BorderRadius.circular(AppTheme.radiusSm),
        border: Border.all(
          color: primaryColor.withOpacity(0.32),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.translate,
                size: 15,
                color: primaryColor,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  _label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: primaryColor,
                    letterSpacing: 0,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // 占满宽度，让从右到左的译文靠右对齐。
          SizedBox(
            width: double.infinity,
            child: Text(
              text,
              textDirection: contentTextDirection(
                text,
                fallback: Directionality.of(context),
              ),
              style: TextStyle(
                fontSize: 14,
                height: 1.55,
                fontWeight: FontWeight.w500,
                color: inkColor,
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String get _label {
    final languageName = UserState.languageNames[languageCode] ?? languageCode;
    final translation =
        AppStrings.getWithLanguage(languageCode, 'translation').trim();

    if (languageCode == 'zh') {
      return '$languageName$translation';
    }
    return '$languageName $translation';
  }
}
