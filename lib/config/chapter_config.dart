import '../models/chapter.dart';

/// 章节配置
/// 根据意大利交通部官方规则定义的25个章节
class ChapterConfig {
  /// 所有章節列表（1-25）
  static List<ChapterModel> chapters = [
    // 主要章节（1-15）
    const ChapterModel(
      id: 1,
      titleIt: 'Segnaletica stradale',
      titleTranslations: {
        'zh': '交通标志',
        'en': 'Road Signs',
        'ru': 'Дорожные знаки',
        'ur': 'سڑک کے نشانات',
        'pa': 'ਸੜਕ ਦੇ ਨਿਸ਼ਾਨ',
        'uk': 'Дорожні знаки',
      },
      isPrincipal: true,
    ),
    const ChapterModel(
      id: 2,
      titleIt: 'Precedenza',
      titleTranslations: {
        'zh': '优先通行权',
        'en': 'Right of Way',
        'ru': 'Преимущество',
        'ur': 'ترجیح',
        'pa': 'ਤਰਜੀਹ',
        'uk': 'Перевага',
      },
      isPrincipal: true,
    ),
    const ChapterModel(
      id: 3,
      titleIt: 'Sosta e fermata',
      titleTranslations: {
        'zh': '停车与停止',
        'en': 'Parking and Stopping',
        'ru': 'Стоянка и остановка',
        'ur': 'پارکنگ اور رکنا',
        'pa': 'ਪਾਰਕਿੰਗ ਅਤੇ ਰੁਕਣਾ',
        'uk': 'Стоянка та зупинка',
      },
      isPrincipal: true,
    ),
    const ChapterModel(
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
    const ChapterModel(
      id: 5,
      titleIt: 'Sorpasso',
      titleTranslations: {
        'zh': '超车',
        'en': 'Overtaking',
        'ru': 'Обгон',
        'ur': 'اوورٹیکنگ',
        'pa': 'ਓਵਰਟੇਕਿੰਗ',
        'uk': 'Обгін',
      },
      isPrincipal: true,
    ),
    const ChapterModel(
      id: 6,
      titleIt: 'Distanza di sicurezza',
      titleTranslations: {
        'zh': '安全距离',
        'en': 'Safety Distance',
        'ru': 'Безопасная дистанция',
        'ur': 'سیفٹی فاصلہ',
        'pa': 'ਸੁਰੱਖਿਆ ਦੂਰੀ',
        'uk': 'Безпечна відстань',
      },
      isPrincipal: true,
    ),
    const ChapterModel(
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
    const ChapterModel(
      id: 8,
      titleIt: 'Curve e cambiamenti di carreggiata',
      titleTranslations: {
        'zh': '弯道与变道',
        'en': 'Curves and Lane Changes',
        'ru': 'Повороты и смена полосы',
        'ur': 'کرونا اور لین تبدیل',
        'pa': 'ਮੋੜ ਅਤੇ ਲੇਨ ਬਦਲਣਾ',
        'uk': 'Повороти та зміна смуги',
      },
      isPrincipal: true,
    ),
    const ChapterModel(
      id: 9,
      titleIt: 'Veicoli e loro caratteristiche',
      titleTranslations: {
        'zh': '车辆及其特征',
        'en': 'Vehicles and Their Characteristics',
        'ru': 'Транспортные средства и их характеристики',
        'ur': 'گاڑیاں اور ان کی خصوصیات',
        'pa': 'ਵਾਹਨ ਅਤੇ ਉਨ੍ਹਾਂ ਦੀਆਂ ਵਿਸ਼ੇਸ਼ਤਾਵਾਂ',
        'uk': 'Транспортні засоби та їх характеристики',
      },
      isPrincipal: true,
    ),
    const ChapterModel(
      id: 10,
      titleIt: 'Documenti di circolazione',
      titleTranslations: {
        'zh': '行驶证件',
        'en': 'Driving Documents',
        'ru': 'Документы для вождения',
        'ur': 'ڈرائیونگ دستاویزات',
        'pa': 'ਡਰਾਈਵਿੰਗ ਦਸਤਾਵੇਜ਼',
        'uk': 'Документи для водіння',
      },
      isPrincipal: true,
    ),
    const ChapterModel(
      id: 11,
      titleIt: 'Guida in condizioni difficili',
      titleTranslations: {
        'zh': '困难条件下的驾驶',
        'en': 'Driving in Difficult Conditions',
        'ru': 'Вождение в сложных условиях',
        'ur': 'مشکل حالات میں ڈرائیونگ',
        'pa': 'ਮੁਸ਼ਕਲ ਹਾਲਤਾਂ ਵਿੱਚ ਡਰਾਈਵਿੰਗ',
        'uk': 'Керування в складних умовах',
      },
      isPrincipal: true,
    ),
    const ChapterModel(
      id: 12,
      titleIt: 'Comportamento in caso di incidente',
      titleTranslations: {
        'zh': '事故处理',
        'en': 'Behavior in Case of Accident',
        'ru': 'Поведение при аварии',
        'ur': 'حادثے کی صورت میں رویہ',
        'pa': 'ਘਟਨਾ ਦੀ ਸਥਿਤੀ ਵਿੱਚ ਵਿਵਹਾਰ',
        'uk': 'Поведінка під час аварії',
      },
      isPrincipal: true,
    ),
    const ChapterModel(
      id: 13,
      titleIt: 'Limiti e divieti',
      titleTranslations: {
        'zh': '限制与禁止',
        'en': 'Limits and Prohibitions',
        'ru': 'Ограничения и запреты',
        'ur': 'حدود اور پابندیاں',
        'pa': 'ਸੀਮਾਵਾਂ ਅਤੇ ਪਾਬੰਦੀਆਂ',
        'uk': 'Обмеження та заборони',
      },
      isPrincipal: true,
    ),
    const ChapterModel(
      id: 14,
      titleIt: 'Segnali luminosi',
      titleTranslations: {
        'zh': '交通信号灯',
        'en': 'Traffic Lights',
        'ru': 'Светофоры',
        'ur': 'ٹریفک لائٹس',
        'pa': 'ਟ੍ਰੈਫਿਕ ਲਾਈਟਾਂ',
        'uk': 'Світлофори',
      },
      isPrincipal: true,
    ),
    const ChapterModel(
      id: 15,
      titleIt: 'Regole generali di comportamento',
      titleTranslations: {
        'zh': '一般行为规则',
        'en': 'General Behavior Rules',
        'ru': 'Общие правила поведения',
        'ur': 'عمومی رویے کے قواعد',
        'pa': 'ਸਧਾਰਨ ਵਿਵਹਾਰ ਦੇ ਨਿਯਮ',
        'uk': 'Загальні правила поведінки',
      },
      isPrincipal: true,
    ),
    
    // 次要章节（16-25）
    const ChapterModel(
      id: 16,
      titleIt: 'Norme per la circolazione dei veicoli',
      titleTranslations: {
        'zh': '车辆通行规则',
        'en': 'Vehicle Traffic Rules',
        'ru': 'Правила движения транспортных средств',
        'ur': 'گاڑیوں کی ٹریفک قواعد',
        'pa': 'ਵਾਹਨ ਟ੍ਰੈਫਿਕ ਨਿਯਮ',
        'uk': 'Правила руху транспортних засобів',
      },
      isPrincipal: false,
    ),
    const ChapterModel(
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
    const ChapterModel(
      id: 18,
      titleIt: 'Circolazione dei ciclisti',
      titleTranslations: {
        'zh': '自行车通行',
        'en': 'Cyclist Traffic',
        'ru': 'Движение велосипедистов',
        'ur': 'سائیکل سواروں کی ٹریفک',
        'pa': 'ਸਾਈਕਲ ਸਵਾਰਾਂ ਦੀ ਟ੍ਰੈਫਿਕ',
        'uk': 'Рух велосипедистів',
      },
      isPrincipal: false,
    ),
    const ChapterModel(
      id: 19,
      titleIt: 'Norme di comportamento per i conducenti',
      titleTranslations: {
        'zh': '驾驶员行为规范',
        'en': 'Driver Behavior Standards',
        'ru': 'Нормы поведения водителей',
        'ur': 'ڈرائیورز کے رویے کے معیارات',
        'pa': 'ਡਰਾਈਵਰਾਂ ਦੇ ਵਿਵਹਾਰ ਦੇ ਮਾਪਦੰਡ',
        'uk': 'Норми поведінки водіїв',
      },
      isPrincipal: false,
    ),
    const ChapterModel(
      id: 20,
      titleIt: 'Uso dei dispositivi di segnalazione',
      titleTranslations: {
        'zh': '信号装置的使用',
        'en': 'Use of Signaling Devices',
        'ru': 'Использование сигнальных устройств',
        'ur': 'سگنلنگ ڈیوائسز کا استعمال',
        'pa': 'ਸਿਗਨਲਿੰਗ ਡਿਵਾਈਸਾਂ ਦਾ ਉਪਯੋਗ',
        'uk': 'Використання сигнальних пристроїв',
      },
      isPrincipal: false,
    ),
    const ChapterModel(
      id: 21,
      titleIt: 'Norme per il trasporto di persone e cose',
      titleTranslations: {
        'zh': '人员与物品运输规范',
        'en': 'Rules for Transporting People and Goods',
        'ru': 'Правила перевозки людей и грузов',
        'ur': 'لوگوں اور سامان کی نقل و حمل کے قواعد',
        'pa': 'ਲੋਕਾਂ ਅਤੇ ਸਾਮਾਨ ਦੀ ਢੋਆ-ਢੁਆਈ ਦੇ ਨਿਯਮ',
        'uk': 'Правила перевезення людей та вантажів',
      },
      isPrincipal: false,
    ),
    const ChapterModel(
      id: 22,
      titleIt: 'Guida ecologica',
      titleTranslations: {
        'zh': '环保驾驶',
        'en': 'Ecological Driving',
        'ru': 'Экологическое вождение',
        'ur': 'ماحولیاتی ڈرائیونگ',
        'pa': 'ਪਰਿਆਵਰਣਕ ਡਰਾਈਵਿੰਗ',
        'uk': 'Екологічне керування',
      },
      isPrincipal: false,
    ),
    const ChapterModel(
      id: 23,
      titleIt: 'Uso delle cinture di sicurezza',
      titleTranslations: {
        'zh': '安全带的使用',
        'en': 'Use of Seat Belts',
        'ru': 'Использование ремней безопасности',
        'ur': 'سیٹ بیلٹ کا استعمال',
        'pa': 'ਸੀਟ ਬੈਲਟ ਦਾ ਉਪਯੋਗ',
        'uk': 'Використання ременів безпеки',
      },
      isPrincipal: false,
    ),
    const ChapterModel(
      id: 24,
      titleIt: 'Norme per la circolazione dei veicoli pubblici',
      titleTranslations: {
        'zh': '公共车辆通行规则',
        'en': 'Public Vehicle Traffic Rules',
        'ru': 'Правила движения общественного транспорта',
        'ur': 'عوامی گاڑیوں کی ٹریفک قواعد',
        'pa': 'ਜਨਤਕ ਵਾਹਨ ਟ੍ਰੈਫਿਕ ਨਿਯਮ',
        'uk': 'Правила руху громадського транспорту',
      },
      isPrincipal: false,
    ),
    const ChapterModel(
      id: 25,
      titleIt: 'Norme per la circolazione dei veicoli pesanti',
      titleTranslations: {
        'zh': '重型车辆通行规则',
        'en': 'Heavy Vehicle Traffic Rules',
        'ru': 'Правила движения тяжелых транспортных средств',
        'ur': 'بھاری گاڑیوں کی ٹریفک قواعد',
        'pa': 'ਭਾਰੀ ਵਾਹਨ ਟ੍ਰੈਫਿਕ ਨਿਯਮ',
        'uk': 'Правила руху важких транспортних засобів',
      },
      isPrincipal: false,
    ),
  ];
  
  /// 获取所有主要章节（1-15）
  /// 按章节ID排序，确保顺序正确
  static List<ChapterModel> get principalChapters {
    return chapters
        .where((chapter) => chapter.isPrincipal)
        .toList()
      ..sort((a, b) => a.id.compareTo(b.id));
  }
  
  /// 获取所有次要章节（16-25）
  /// 按章节ID排序，确保顺序正确
  static List<ChapterModel> get secondaryChapters {
    return chapters
        .where((chapter) => !chapter.isPrincipal)
        .toList()
      ..sort((a, b) => a.id.compareTo(b.id));
  }
  
  /// 根据ID获取章节
  static ChapterModel? getChapterById(int id) {
    try {
      return chapters.firstWhere((chapter) => chapter.id == id);
    } catch (e) {
      return null;
    }
  }
  
  /// 获取章节总数
  static int get totalChapters => chapters.length;
  
  /// 获取主要章节数量
  static int get principalChaptersCount => principalChapters.length;
  
  /// 获取次要章节数量
  static int get secondaryChaptersCount => secondaryChapters.length;
}

