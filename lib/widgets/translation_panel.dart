import 'package:flutter/material.dart';

import '../config/app_strings.dart';
import '../config/app_theme.dart';
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.primarySoft.withOpacity(0.78),
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        border: Border.all(color: AppTheme.primary.withOpacity(0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.translate,
                size: 15,
                color: AppTheme.primary,
              ),
              const SizedBox(width: 6),
              Text(
                _label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.primary,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            text,
            style: const TextStyle(
              fontSize: 14,
              height: 1.55,
              fontWeight: FontWeight.w500,
              color: AppTheme.ink,
              letterSpacing: 0,
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
