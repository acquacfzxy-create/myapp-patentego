import 'dart:convert';

enum VoicePackDownloadStatus {
  notDownloaded,
  downloading,
  paused,
  installed,
  failed,
}

/// Metadata for one downloadable Italian voice pack.
///
/// The manifest is intentionally validated strictly so malformed remote data
/// never becomes a local file-system path.
class VoicePack {
  const VoicePack({
    required this.id,
    required this.chapterId,
    required this.displayName,
    required this.version,
    required this.questionCount,
    required this.sizeBytes,
    required this.sha256,
    required this.storagePath,
    required this.indexFile,
  });

  final String id;
  final int? chapterId;
  final String displayName;
  final String version;
  final int questionCount;
  final int sizeBytes;
  final String sha256;
  final String storagePath;
  final String indexFile;

  /// Alias for callers that use title terminology.
  String get title => displayName;

  bool get isAllQuestions => id == 'all_questions';

  factory VoicePack.fromJson(Map<String, dynamic> json) {
    const allowedKeys = <String>{
      'id',
      'chapterId',
      'displayName',
      'title',
      'version',
      'questionCount',
      'sizeBytes',
      'sha256',
      'storagePath',
      'indexFile',
    };
    final unknownKeys = json.keys.toSet().difference(allowedKeys);
    if (unknownKeys.isNotEmpty) {
      throw const FormatException('Voice pack contains unknown fields.');
    }

    final id = _requiredString(json, 'id');
    final idMatch = RegExp(r'^chapter_(\d{2})$').firstMatch(id);
    if (id != 'uncategorized' && id != 'all_questions' && idMatch == null) {
      throw const FormatException('Voice pack id is invalid.');
    }

    final chapterValue = json['chapterId'];
    if (chapterValue != null && chapterValue is! int) {
      throw const FormatException('chapterId must be an integer or null.');
    }
    final chapterId = chapterValue as int?;
    if (id == 'uncategorized' || id == 'all_questions') {
      if (chapterId != null) {
        throw const FormatException(
          'A non-chapter pack must have a null chapterId.',
        );
      }
    } else {
      if (chapterId == null || chapterId <= 0) {
        throw const FormatException('A chapter pack needs a valid chapterId.');
      }
      final idChapter = int.parse(idMatch!.group(1)!);
      if (idChapter != chapterId) {
        throw const FormatException('Voice pack id and chapterId disagree.');
      }
    }

    final hasDisplayName = json.containsKey('displayName');
    final hasTitle = json.containsKey('title');
    if (hasDisplayName == hasTitle) {
      throw const FormatException(
        'Voice pack needs exactly one displayName or title.',
      );
    }
    final displayName = _requiredString(
      json,
      hasDisplayName ? 'displayName' : 'title',
    );
    final version = _requiredString(json, 'version');
    if (!_isSafePathSegment(version)) {
      throw const FormatException('Voice pack version is invalid.');
    }

    final questionCount = _requiredPositiveInt(json, 'questionCount');
    final sizeBytes = _requiredPositiveInt(json, 'sizeBytes');
    final checksum = _requiredString(json, 'sha256').toLowerCase();
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(checksum)) {
      throw const FormatException('Voice pack SHA-256 is invalid.');
    }

    final storagePath = _requiredString(json, 'storagePath');
    if (!storagePath.startsWith('voice_packs/it/') ||
        !_isSafeRelativePath(storagePath) ||
        !storagePath.toLowerCase().endsWith('.zip')) {
      throw const FormatException('Voice pack storagePath is invalid.');
    }
    final indexFile = _requiredString(json, 'indexFile');
    if (!_isSafeRelativePath(indexFile) ||
        !indexFile.toLowerCase().endsWith('.json')) {
      throw const FormatException('Voice pack indexFile is invalid.');
    }

    return VoicePack(
      id: id,
      chapterId: chapterId,
      displayName: displayName,
      version: version,
      questionCount: questionCount,
      sizeBytes: sizeBytes,
      sha256: checksum,
      storagePath: storagePath,
      indexFile: indexFile,
    );
  }

  static List<VoicePack> decodeCatalog(String source) {
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException {
      throw const FormatException('Voice pack catalog is not valid JSON.');
    }
    const catalogKeys = <String>{
      'schema',
      'language',
      'voice',
      'version',
      'packs',
    };
    if (decoded is! Map<String, dynamic> ||
        decoded.keys.toSet().difference(catalogKeys).isNotEmpty ||
        catalogKeys.difference(decoded.keys.toSet()).isNotEmpty ||
        decoded['schema'] != 1 ||
        decoded['language'] != 'it-IT' ||
        decoded['voice'] is! String ||
        !_isSafePathSegment(decoded['voice'] as String) ||
        decoded['version'] is! String ||
        !_isSafePathSegment(decoded['version'] as String) ||
        decoded['packs'] is! List<dynamic>) {
      throw const FormatException(
        'Voice pack catalog metadata or packs array is invalid.',
      );
    }

    final catalogVersion = decoded['version'] as String;
    final packs = <VoicePack>[];
    final ids = <String>{};
    for (final entry in decoded['packs'] as List<dynamic>) {
      if (entry is! Map<String, dynamic>) {
        throw const FormatException('Every voice pack must be an object.');
      }
      final pack = VoicePack.fromJson(entry);
      if (pack.version != catalogVersion ||
          !pack.storagePath.startsWith('voice_packs/it/$catalogVersion/')) {
        throw const FormatException(
          'Voice pack version or storagePath disagrees with the catalog.',
        );
      }
      if (!ids.add(pack.id)) {
        throw const FormatException('Voice pack ids must be unique.');
      }
      packs.add(pack);
    }
    return List<VoicePack>.unmodifiable(packs);
  }

  static String _requiredString(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is! String || value.trim().isEmpty || value != value.trim()) {
      throw FormatException('$key must be a non-empty trimmed string.');
    }
    return value;
  }

  static int _requiredPositiveInt(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is! int || value <= 0) {
      throw FormatException('$key must be a positive integer.');
    }
    return value;
  }

  static bool _isSafePathSegment(String value) {
    return value != '.' &&
        value != '..' &&
        RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]*$').hasMatch(value);
  }

  static bool _isSafeRelativePath(String value) {
    if (value.isEmpty ||
        value.startsWith('/') ||
        value.startsWith(r'\') ||
        value.contains(r'\') ||
        value.contains('?') ||
        value.contains('#')) {
      return false;
    }
    final segments = value.split('/');
    return segments.every(_isSafePathSegment);
  }
}

class VoicePackState {
  VoicePackState({
    required this.pack,
    this.status = VoicePackDownloadStatus.notDownloaded,
    this.progress = 0,
    this.downloadedBytes = 0,
    int? totalBytes,
    this.error,
  }) : totalBytes = totalBytes ?? pack.sizeBytes;

  static const Object _notProvided = Object();

  final VoicePack pack;
  final VoicePackDownloadStatus status;
  final double progress;
  final int downloadedBytes;
  final int totalBytes;
  final String? error;

  VoicePackState copyWith({
    VoicePack? pack,
    VoicePackDownloadStatus? status,
    double? progress,
    int? downloadedBytes,
    int? totalBytes,
    Object? error = _notProvided,
  }) {
    return VoicePackState(
      pack: pack ?? this.pack,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      downloadedBytes: downloadedBytes ?? this.downloadedBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      error: identical(error, _notProvided) ? this.error : error as String?,
    );
  }
}
