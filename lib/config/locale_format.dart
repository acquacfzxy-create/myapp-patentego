/// 按界面语言格式化日期与文件大小（不依赖 intl，覆盖 App 实际支持的七种语言）。
class LocaleFormat {
  LocaleFormat._();

  /// 日期：zh 用「年月日」，ru/uk/it 用点或斜杠分隔的「日.月.年」，其余用「日/月/年」。
  static String date(String language, DateTime date) {
    final d = date.day.toString().padLeft(2, '0');
    final m = date.month.toString().padLeft(2, '0');
    final y = date.year.toString();
    switch (language) {
      case 'zh':
        return '$y年${date.month}月${date.day}日';
      case 'en':
        return '$y-$m-$d';
      case 'ru':
      case 'uk':
        return '$d.$m.$y';
      default:
        return '$d/$m/$y';
    }
  }

  /// 图表等处的短日期（不含年份）。zh 为「月/日」，en 为 ISO 式「MM-dd」，
  /// ru/uk 为「dd.MM」，其余（it/pa/ur）为「日/月」，避免把 3/7 读成 7 月 3 日。
  static String shortDate(String language, DateTime date) {
    final d = date.day.toString().padLeft(2, '0');
    final m = date.month.toString().padLeft(2, '0');
    switch (language) {
      case 'zh':
        return '${date.month}/${date.day}';
      case 'en':
        return '$m-$d';
      case 'ru':
      case 'uk':
        return '$d.$m';
      default:
        return '${date.day}/${date.month}';
    }
  }

  /// 带小数的数值：ru/uk/it 使用逗号作小数点。
  static String decimal(String language, double value, int fractionDigits) {
    final text = value.toStringAsFixed(fractionDigits);
    return language == 'ru' || language == 'uk' || language == 'it'
        ? text.replaceAll('.', ',')
        : text;
  }

  /// 文件大小：ru/uk/it 使用逗号作小数点，ru/uk 使用西里尔字母单位。
  static String fileSize(String language, int bytes) {
    const units = ['KB', 'MB', 'GB'];
    const cyrillicUnits = ['КБ', 'МБ', 'ГБ'];
    final useCyrillic = language == 'ru' || language == 'uk';
    final decimalComma =
        language == 'ru' || language == 'uk' || language == 'it';

    if (bytes < 1024) {
      return '$bytes ${useCyrillic ? 'Б' : 'B'}';
    }
    var value = bytes / 1024;
    var index = 0;
    while (value >= 1024 && index < units.length - 1) {
      value /= 1024;
      index++;
    }
    var number = value.toStringAsFixed(1);
    if (decimalComma) number = number.replaceAll('.', ',');
    final unit = useCyrillic ? cyrillicUnits[index] : units[index];
    return '$number $unit';
  }
}
