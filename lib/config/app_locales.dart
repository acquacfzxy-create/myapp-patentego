import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../models/user_state.dart';

/// App 界面语言与 Flutter 内置组件（复制/粘贴菜单、返回按钮提示、对话框语义等）的本地化配置。
///
/// 只声明实际可选的界面语言（[UserState.supportedLanguages]）；意大利语仅用于题干，
/// 不作为界面语言。
class AppLocales {
  AppLocales._();

  static const List<LocalizationsDelegate<dynamic>> delegates =
      GlobalMaterialLocalizations.delegates;

  static final List<Locale> supportedLocales = [
    for (final language in UserState.supportedLanguages) Locale(language),
  ];

  /// 界面语言代码对应的 Locale；未知代码回退到默认中文。
  static Locale localeFor(String language) =>
      UserState.supportedLanguages.contains(language)
          ? Locale(language)
          : const Locale('zh');
}
