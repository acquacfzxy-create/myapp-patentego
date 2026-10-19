import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';

import '../models/voice_pack.dart';

typedef WebVoiceDataLoader = Future<Uint8List?> Function(
  String storagePath,
  int maxBytes,
);
typedef WebVoiceUrlLoader = Future<Uri> Function(String storagePath);

/// Resolves one question to the immutable MP3 used by the native voice pack.
///
/// The Web build reads the existing voice-pack catalog, then a versioned
/// question-to-file index. Audio remains in Firebase Storage and is streamed
/// only after the user taps the listen control.
class WebVoiceStreamService {
  WebVoiceStreamService({
    FirebaseStorage? storage,
    WebVoiceDataLoader? dataLoader,
    WebVoiceUrlLoader? urlLoader,
  })  : _storage = storage,
        _dataLoader = dataLoader,
        _urlLoader = urlLoader;

  static const String catalogStoragePath = 'voice_packs/it/manifest.json';
  static const int _catalogMaxBytes = 512 * 1024;
  static const int _indexMaxBytes = 2 * 1024 * 1024;

  final FirebaseStorage? _storage;
  final WebVoiceDataLoader? _dataLoader;
  final WebVoiceUrlLoader? _urlLoader;
  Future<_WebVoiceIndex>? _indexFuture;
  final Map<String, Future<Uri>> _audioUrlCache = {};

  Future<Uri?> audioUriFor(String questionId) async {
    final normalizedId = questionId.trim();
    if (normalizedId.isEmpty) return null;

    final index = await (_indexFuture ??= _loadIndex());
    final relativePath = index.audioByQuestion[normalizedId];
    if (relativePath == null) return null;
    final storagePath = '${index.storagePrefix}/$relativePath';
    try {
      return await (_audioUrlCache[storagePath] ??= _loadUrl(storagePath));
    } catch (_) {
      _audioUrlCache.remove(storagePath);
      rethrow;
    }
  }

  Future<_WebVoiceIndex> _loadIndex() async {
    final catalogBytes = await _loadData(
      catalogStoragePath,
      _catalogMaxBytes,
    );
    if (catalogBytes == null || catalogBytes.isEmpty) {
      throw const FormatException('The voice catalog is unavailable.');
    }
    final catalog = VoicePack.decodeCatalog(
      utf8.decode(catalogBytes, allowMalformed: false),
    );
    final allQuestions = catalog.where((pack) => pack.isAllQuestions).toList();
    if (allQuestions.length != 1) {
      throw const FormatException(
        'The Web voice stream requires one all-questions voice pack.',
      );
    }

    final pack = allQuestions.single;
    final lastSlash = pack.storagePath.lastIndexOf('/');
    if (lastSlash <= 0) {
      throw const FormatException('The voice-pack path is invalid.');
    }
    final storagePrefix = '${pack.storagePath.substring(0, lastSlash)}/stream';
    final indexBytes = await _loadData(
      '$storagePrefix/${pack.indexFile}',
      _indexMaxBytes,
    );
    if (indexBytes == null || indexBytes.isEmpty) {
      throw const FormatException('The Web voice index is unavailable.');
    }

    final decoded = jsonDecode(utf8.decode(indexBytes, allowMalformed: false));
    if (decoded is! Map || decoded.length != pack.questionCount) {
      throw const FormatException('The Web voice index count is invalid.');
    }
    final audioByQuestion = <String, String>{};
    final seenPaths = <String>{};
    final safeAudioPath = RegExp(r'^audio/q_[a-f0-9]{64}\.mp3$');
    for (final entry in decoded.entries) {
      final id = entry.key.toString().trim();
      final relativePath = entry.value?.toString().trim() ?? '';
      if (id.isEmpty ||
          !safeAudioPath.hasMatch(relativePath) ||
          !seenPaths.add(relativePath)) {
        throw const FormatException('The Web voice index is invalid.');
      }
      audioByQuestion[id] = relativePath;
    }

    return _WebVoiceIndex(
      storagePrefix: storagePrefix,
      audioByQuestion: Map.unmodifiable(audioByQuestion),
    );
  }

  Future<Uint8List?> _loadData(String storagePath, int maxBytes) {
    final loader = _dataLoader;
    if (loader != null) return loader(storagePath, maxBytes);
    return (_storage ?? FirebaseStorage.instance)
        .ref(storagePath)
        .getData(maxBytes);
  }

  Future<Uri> _loadUrl(String storagePath) async {
    final loader = _urlLoader;
    if (loader != null) return loader(storagePath);
    final source = await (_storage ?? FirebaseStorage.instance)
        .ref(storagePath)
        .getDownloadURL();
    return Uri.parse(source);
  }
}

class _WebVoiceIndex {
  const _WebVoiceIndex({
    required this.storagePrefix,
    required this.audioByQuestion,
  });

  final String storagePrefix;
  final Map<String, String> audioByQuestion;
}
