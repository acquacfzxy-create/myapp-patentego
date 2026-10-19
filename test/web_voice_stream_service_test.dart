import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lingua_patente/services/web_voice_stream_service.dart';

void main() {
  const version = 'voice-v1';
  const relativePath =
      'audio/q_b572ebd3a02e4754fca2ce9a36598a20853b3bd645fe725e71f4a08f7bd9b5c7.mp3';

  Map<String, dynamic> catalog({int questionCount = 1}) => {
        'schema': 1,
        'language': 'it-IT',
        'voice': 'it-IT-Chirp3-HD-Algenib',
        'version': version,
        'packs': [
          {
            'id': 'all_questions',
            'chapterId': null,
            'displayName': 'All questions',
            'version': version,
            'questionCount': questionCount,
            'sizeBytes': 100,
            'sha256': List.filled(64, 'a').join(),
            'storagePath': 'voice_packs/it/$version/all_questions.zip',
            'indexFile': 'index.json',
          },
        ],
      };

  Uint8List bytes(Object value) =>
      Uint8List.fromList(utf8.encode(jsonEncode(value)));

  test('resolves a question to the immutable streamed MP3 path', () async {
    final requestedDataPaths = <String>[];
    final requestedAudioPaths = <String>[];
    final service = WebVoiceStreamService(
      dataLoader: (path, _) async {
        requestedDataPaths.add(path);
        return path == WebVoiceStreamService.catalogStoragePath
            ? bytes(catalog())
            : bytes({'1': relativePath});
      },
      urlLoader: (path) async {
        requestedAudioPaths.add(path);
        return Uri.parse('https://example.test/$path');
      },
    );

    final uri = await service.audioUriFor('1');
    final cachedUri = await service.audioUriFor('1');
    expect(
      uri.toString(),
      'https://example.test/voice_packs/it/$version/stream/$relativePath',
    );
    expect(cachedUri, uri);
    expect(requestedDataPaths, [
      'voice_packs/it/manifest.json',
      'voice_packs/it/$version/stream/index.json',
    ]);
    expect(requestedAudioPaths, [
      'voice_packs/it/$version/stream/$relativePath',
    ]);
  });

  test('caches the catalog/index and returns null for an unknown question',
      () async {
    var dataLoads = 0;
    final service = WebVoiceStreamService(
      dataLoader: (path, _) async {
        dataLoads++;
        return path == WebVoiceStreamService.catalogStoragePath
            ? bytes(catalog())
            : bytes({'1': relativePath});
      },
      urlLoader: (path) async => Uri.parse('https://example.test/$path'),
    );

    expect(await service.audioUriFor('missing'), isNull);
    expect(await service.audioUriFor('missing-again'), isNull);
    expect(dataLoads, 2);
  });

  test('rejects unsafe or incomplete stream indexes', () async {
    final unsafe = WebVoiceStreamService(
      dataLoader: (path, _) async =>
          path == WebVoiceStreamService.catalogStoragePath
              ? bytes(catalog())
              : bytes({'1': '../secret.mp3'}),
      urlLoader: (path) async => Uri.parse('https://example.test/$path'),
    );
    await expectLater(
      unsafe.audioUriFor('1'),
      throwsA(isA<FormatException>()),
    );

    final incomplete = WebVoiceStreamService(
      dataLoader: (path, _) async =>
          path == WebVoiceStreamService.catalogStoragePath
              ? bytes(catalog(questionCount: 2))
              : bytes({'1': relativePath}),
      urlLoader: (path) async => Uri.parse('https://example.test/$path'),
    );
    await expectLater(
      incomplete.audioUriFor('1'),
      throwsA(isA<FormatException>()),
    );
  });
}
