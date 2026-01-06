import '../models/chapter.dart';

/// 章節配置
/// 根據意大利交通部官方規則定義的25個章節
class ChapterConfig {
  /// 所有章節列表（1-25）
  static List<ChapterModel> chapters = [
    // 重點章節（1-15）
    ChapterModel(
      id: 1,
      titleIt: 'Segnaletica stradale',
      titleTranslations: {
        'zh': '交通標誌',
        'en': 'Road Signs',
        'ru': 'Дорожные знаки',
        'ur': 'سڑک کے نشانات',
        'pa': 'ਸੜਕ ਦੇ ਨਿਸ਼ਾਨ',
        'uk': 'Дорожні знаки',
      },
      isPrincipal: true,
    ),
    ChapterModel(
      id: 2,
      titleIt: 'Precedenza',
      titleTranslations: {
        'zh': '優先通行權',
        'en': 'Right of Way',
        'ru': 'Преимущество',
        'ur': 'ترجیح',
        'pa': 'ਤਰਜੀਹ',
        'uk': 'Перевага',
      },
      isPrincipal: true,
    ),
    ChapterModel(
      id: 3,
      titleIt: 'Sosta e fermata',
      titleTranslations: {
        'zh': '停車與停止',
        'en': 'Parking and Stopping',
        'ru': 'Стоянка и остановка',
        'ur': 'پارکنگ اور رکنا',
        'pa': 'ਪਾਰਕਿੰਗ ਅਤੇ ਰੁਕਣਾ',
        'uk': 'Стоянка та зупинка',
      },
      isPrincipal: true,
    ),
    ChapterModel(
      id: 4,
      titleIt: 'Velocità',
      titleTranslations: {
        'zh': '速度限制',
        'en': 'Speed Limits',
        'ru': 'Скорость',
        'ur': 'رفتار کی حد',
        'pa': 'ਸਪੀਡ ਦੀ ਹੱਦ',
        'uk': 'Швидкість',
      },
      isPrincipal: true,
    ),
    ChapterModel(
      id: 5,
      titleIt: 'Sorpasso',
      titleTranslations: {
        'zh': '超車',
        'en': 'Overtaking',
        'ru': 'Обгон',
        'ur': 'اوورٹیکنگ',
        'pa': 'ਓਵਰਟੇਕਿੰਗ',
        'uk': 'Обгін',
      },
      isPrincipal: true,
    ),
    ChapterModel(
      id: 6,
      titleIt: 'Distanza di sicurezza',
      titleTranslations: {
        'zh': '安全距離',
        'en': 'Safety Distance',
        'ru': 'Безопасная дистанция',
        'ur': 'سیفٹی فاصلہ',
        'pa': 'ਸੁਰੱਖਿਆ ਦੂਰੀ',
        'uk': 'Безпечна відстань',
      },
      isPrincipal: true,
    ),
    ChapterModel(
      id: 7,
      titleIt: 'Incroci',
      titleTranslations: {
        'zh': '交叉路口',
        'en': 'Intersections',
        'ru': 'Перекрестки',
        'ur': 'انٹرسیکشن',
        'pa': 'ਇੰਟਰਸੈਕਸ਼ਨ',
        'uk': 'Перехрестя',
      },
      isPrincipal: true,
    ),
    ChapterModel(
      id: 8,
      titleIt: 'Curve e cambiamenti di carreggiata',
      titleTranslations: {
        'zh': '彎道與變道',
        'en': 'Curves and Lane Changes',
        'ru': 'Повороты и смена полосы',
        'ur': 'کرونا اور لین تبدیل',
        'pa': 'ਮੋੜ ਅਤੇ ਲੇਨ ਬਦਲਣਾ',
        'uk': 'Повороти та зміна смуги',
      },
      isPrincipal: true,
    ),
    ChapterModel(
      id: 9,
      titleIt: 'Veicoli e loro caratteristiche',
      titleTranslations: {
        'zh': '車輛及其特徵',
        'en': 'Vehicles and Their Characteristics',
        'ru': 'Транспортные средства и их характеристики',
        'ur': 'گاڑیاں اور ان کی خصوصیات',
        'pa': 'ਵਾਹਨ ਅਤੇ ਉਨ੍ਹਾਂ ਦੀਆਂ ਵਿਸ਼ੇਸ਼ਤਾਵਾਂ',
        'uk': 'Транспортні засоби та їх характеристики',
      },
      isPrincipal: true,
    ),
    ChapterModel(
      id: 10,
      titleIt: 'Documenti di circolazione',
      titleTranslations: {
        'zh': '行駛證件',
        'en': 'Driving Documents',
        'ru': 'Документы для вождения',
        'ur': 'ڈرائیونگ دستاویزات',
        'pa': 'ਡਰਾਈਵਿੰਗ ਦਸਤਾਵੇਜ਼',
        'uk': 'Документи для водіння',
      },
      isPrincipal: true,
    ),
    ChapterModel(
      id: 11,
      titleIt: 'Guida in condizioni difficili',
      titleTranslations: {
        'zh': '困難條件下的駕駛',
        'en': 'Driving in Difficult Conditions',
        'ru': 'Вождение в сложных условиях',
        'ur': 'مشکل حالات میں ڈرائیونگ',
        'pa': 'ਮੁਸ਼ਕਲ ਹਾਲਤਾਂ ਵਿੱਚ ਡਰਾਈਵਿੰਗ',
        'uk': 'Керування в складних умовах',
      },
      isPrincipal: true,
    ),
    ChapterModel(
      id: 12,
      titleIt: 'Comportamento in caso di incidente',
      titleTranslations: {
        'zh': '事故處理',
        'en': 'Behavior in Case of Accident',
        'ru': 'Поведение при аварии',
        'ur': 'حادثے کی صورت میں رویہ',
        'pa': 'ਘਟਨਾ ਦੀ ਸਥਿਤੀ ਵਿੱਚ ਵਿਵਹਾਰ',
        'uk': 'Поведінка під час аварії',
      },
      isPrincipal: true,
    ),
    ChapterModel(
      id: 13,
      titleIt: 'Limiti e divieti',
      titleTranslations: {
        'zh': '限制與禁止',
        'en': 'Limits and Prohibitions',
        'ru': 'Ограничения и запреты',
        'ur': 'حدود اور پابندیاں',
        'pa': 'ਸੀਮਾਵਾਂ ਅਤੇ ਪਾਬੰਦੀਆਂ',
        'uk': 'Обмеження та заборони',
      },
      isPrincipal: true,
    ),
    ChapterModel(
      id: 14,
      titleIt: 'Segnali luminosi',
      titleTranslations: {
        'zh': '交通信號燈',
        'en': 'Traffic Lights',
        'ru': 'Светофоры',
        'ur': 'ٹریفک لائٹس',
        'pa': 'ਟ੍ਰੈਫਿਕ ਲਾਈਟਾਂ',
        'uk': 'Світлофори',
      },
      isPrincipal: true,
    ),
    ChapterModel(
      id: 15,
      titleIt: 'Regole generali di comportamento',
      titleTranslations: {
        'zh': '一般行為規則',
        'en': 'General Behavior Rules',
        'ru': 'Общие правила поведения',
        'ur': 'عمومی رویے کے قواعد',
        'pa': 'ਸਧਾਰਨ ਵਿਵਹਾਰ ਦੇ ਨਿਯਮ',
        'uk': 'Загальні правила поведінки',
      },
      isPrincipal: true,
    ),
    
    // 次要章節（16-25）
    ChapterModel(
      id: 16,
      titleIt: 'Norme per la circolazione dei veicoli',
      titleTranslations: {
        'zh': '車輛通行規則',
        'en': 'Vehicle Traffic Rules',
        'ru': 'Правила движения транспортных средств',
        'ur': 'گاڑیوں کی ٹریفک قواعد',
        'pa': 'ਵਾਹਨ ਟ੍ਰੈਫਿਕ ਨਿਯਮ',
        'uk': 'Правила руху транспортних засобів',
      },
      isPrincipal: false,
    ),
    ChapterModel(
      id: 17,
      titleIt: 'Circolazione dei pedoni',
      titleTranslations: {
        'zh': '行人通行',
        'en': 'Pedestrian Traffic',
        'ru': 'Движение пешеходов',
        'ur': 'پیدل چلنے والوں کی ٹریفک',
        'pa': 'ਪੈਦਲ ਚੱਲਣ ਵਾਲਿਆਂ ਦੀ ਟ੍ਰੈਫਿਕ',
        'uk': 'Рух пішоходів',
      },
      isPrincipal: false,
    ),
    ChapterModel(
      id: 18,
      titleIt: 'Circolazione dei ciclisti',
      titleTranslations: {
        'zh': '自行車通行',
        'en': 'Cyclist Traffic',
        'ru': 'Движение велосипедистов',
        'ur': 'سائیکل سواروں کی ٹریفک',
        'pa': 'ਸਾਈਕਲ ਸਵਾਰਾਂ ਦੀ ਟ੍ਰੈਫਿਕ',
        'uk': 'Рух велосипедистів',
      },
      isPrincipal: false,
    ),
    ChapterModel(
      id: 19,
      titleIt: 'Norme di comportamento per i conducenti',
      titleTranslations: {
        'zh': '駕駛員行為規範',
        'en': 'Driver Behavior Standards',
        'ru': 'Нормы поведения водителей',
        'ur': 'ڈرائیورز کے رویے کے معیارات',
        'pa': 'ਡਰਾਈਵਰਾਂ ਦੇ ਵਿਵਹਾਰ ਦੇ ਮਾਪਦੰਡ',
        'uk': 'Норми поведінки водіїв',
      },
      isPrincipal: false,
    ),
    ChapterModel(
      id: 20,
      titleIt: 'Uso dei dispositivi di segnalazione',
      titleTranslations: {
        'zh': '信號裝置的使用',
        'en': 'Use of Signaling Devices',
        'ru': 'Использование сигнальных устройств',
        'ur': 'سگنلنگ ڈیوائسز کا استعمال',
        'pa': 'ਸਿਗਨਲਿੰਗ ਡਿਵਾਈਸਾਂ ਦਾ ਉਪਯੋਗ',
        'uk': 'Використання сигнальних пристроїв',
      },
      isPrincipal: false,
    ),
    ChapterModel(
      id: 21,
      titleIt: 'Norme per il trasporto di persone e cose',
      titleTranslations: {
        'zh': '人員與物品運輸規範',
        'en': 'Rules for Transporting People and Goods',
        'ru': 'Правила перевозки людей и грузов',
        'ur': 'لوگوں اور سامان کی نقل و حمل کے قواعد',
        'pa': 'ਲੋਕਾਂ ਅਤੇ ਸਾਮਾਨ ਦੀ ਢੋਆ-ਢੁਆਈ ਦੇ ਨਿਯਮ',
        'uk': 'Правила перевезення людей та вантажів',
      },
      isPrincipal: false,
    ),
    ChapterModel(
      id: 22,
      titleIt: 'Guida ecologica',
      titleTranslations: {
        'zh': '環保駕駛',
        'en': 'Ecological Driving',
        'ru': 'Экологическое вождение',
        'ur': 'ماحولیاتی ڈرائیونگ',
        'pa': 'ਪਰਿਆਵਰਣਕ ਡਰਾਈਵਿੰਗ',
        'uk': 'Екологічне керування',
      },
      isPrincipal: false,
    ),
    ChapterModel(
      id: 23,
      titleIt: 'Uso delle cinture di sicurezza',
      titleTranslations: {
        'zh': '安全帶的使用',
        'en': 'Use of Seat Belts',
        'ru': 'Использование ремней безопасности',
        'ur': 'سیٹ بیلٹ کا استعمال',
        'pa': 'ਸੀਟ ਬੈਲਟ ਦਾ ਉਪਯੋਗ',
        'uk': 'Використання ременів безпеки',
      },
      isPrincipal: false,
    ),
    ChapterModel(
      id: 24,
      titleIt: 'Norme per la circolazione dei veicoli pubblici',
      titleTranslations: {
        'zh': '公共車輛通行規則',
        'en': 'Public Vehicle Traffic Rules',
        'ru': 'Правила движения общественного транспорта',
        'ur': 'عوامی گاڑیوں کی ٹریفک قواعد',
        'pa': 'ਜਨਤਕ ਵਾਹਨ ਟ੍ਰੈਫਿਕ ਨਿਯਮ',
        'uk': 'Правила руху громадського транспорту',
      },
      isPrincipal: false,
    ),
    ChapterModel(
      id: 25,
      titleIt: 'Norme per la circolazione dei veicoli pesanti',
      titleTranslations: {
        'zh': '重型車輛通行規則',
        'en': 'Heavy Vehicle Traffic Rules',
        'ru': 'Правила движения тяжелых транспортных средств',
        'ur': 'بھاری گاڑیوں کی ٹریفک قواعد',
        'pa': 'ਭਾਰੀ ਵਾਹਨ ਟ੍ਰੈਫਿਕ ਨਿਯਮ',
        'uk': 'Правила руху важких транспортних засобів',
      },
      isPrincipal: false,
    ),
  ];
  
  /// 獲取所有重點章節（1-15）
  /// 按章節ID排序，確保順序正確
  static List<ChapterModel> get principalChapters {
    return chapters
        .where((chapter) => chapter.isPrincipal)
        .toList()
      ..sort((a, b) => a.id.compareTo(b.id));
  }
  
  /// 獲取所有次要章節（16-25）
  /// 按章節ID排序，確保順序正確
  static List<ChapterModel> get secondaryChapters {
    return chapters
        .where((chapter) => !chapter.isPrincipal)
        .toList()
      ..sort((a, b) => a.id.compareTo(b.id));
  }
  
  /// 根據ID獲取章節
  static ChapterModel? getChapterById(int id) {
    try {
      return chapters.firstWhere((chapter) => chapter.id == id);
    } catch (e) {
      return null;
    }
  }
  
  /// 獲取章節總數
  static int get totalChapters => chapters.length;
  
  /// 獲取重點章節數量
  static int get principalChaptersCount => principalChapters.length;
  
  /// 獲取次要章節數量
  static int get secondaryChaptersCount => secondaryChapters.length;
}

