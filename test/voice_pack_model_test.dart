import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lingua_patente/models/voice_pack.dart';

void main() {
  group('VoicePack', () {
    test('decodes a strictly valid catalog', () {
      final packs = VoicePack.decodeCatalog(
        jsonEncode({
          'schema': 1,
          'language': 'it-IT',
          'voice': 'it-IT-DiegoNeural',
          'version': '1.0.0',
          'packs': [
            _validPack(),
            _validPack(
              id: 'uncategorized',
              chapterId: null,
              displayName: 'Altre domande',
              storagePath: 'voice_packs/it/1.0.0/uncategorized-v1.zip',
            ),
          ],
        }),
      );

      expect(packs, hasLength(2));
      expect(packs.first.id, 'chapter_01');
      expect(packs.first.chapterId, 1);
      expect(packs.first.displayName, 'Capitolo 1');
      expect(packs.first.title, 'Capitolo 1');
      expect(packs.last.chapterId, isNull);
    });

    test('accepts title as the displayName alias', () {
      final json = _validPack()..['title'] = jsonDecode(jsonEncode('Uno'));
      json.remove('displayName');

      final pack = VoicePack.fromJson(json);

      expect(pack.displayName, 'Uno');
      expect(pack.title, 'Uno');
    });

    test('accepts one all-questions pack with a null chapter id', () {
      final pack = VoicePack.fromJson(
        _validPack(
          id: 'all_questions',
          chapterId: null,
          displayName: 'All questions',
          storagePath: 'voice_packs/it/1.0.0/all_questions-v1.zip',
        ),
      );

      expect(pack.isAllQuestions, isTrue);
      expect(pack.chapterId, isNull);
    });

    test('strictly rejects non-integer chapter ids', () {
      final json = _validPack()..['chapterId'] = '1';

      expect(() => VoicePack.fromJson(json), throwsFormatException);
    });

    test('rejects mismatched ids and unsafe storage paths', () {
      expect(
        () => VoicePack.fromJson(_validPack()..['chapterId'] = 2),
        throwsFormatException,
      );
      expect(
        () => VoicePack.fromJson(
          _validPack()..['storagePath'] = 'voice_packs/it/../secret.zip',
        ),
        throwsFormatException,
      );
    });

    test('rejects unknown pack and catalog fields', () {
      expect(
        () => VoicePack.fromJson(_validPack()..['unexpected'] = true),
        throwsFormatException,
      );
      expect(
        () => VoicePack.decodeCatalog(
          jsonEncode({
            'schema': 1,
            'language': 'it-IT',
            'voice': 'it-IT-DiegoNeural',
            'version': '1.0.0',
            'generatedAt': '2026-08-10T00:00:00Z',
            'packs': [_validPack()],
          }),
        ),
        throwsFormatException,
      );
    });

    test('rejects duplicate ids and invalid checksums', () {
      expect(
        () => VoicePack.decodeCatalog(
          jsonEncode({
            'schema': 1,
            'language': 'it-IT',
            'voice': 'it-IT-DiegoNeural',
            'version': '1.0.0',
            'packs': [_validPack(), _validPack()],
          }),
        ),
        throwsFormatException,
      );
      expect(
        () => VoicePack.fromJson(_validPack()..['sha256'] = 'not-a-hash'),
        throwsFormatException,
      );
    });

    test('rejects pack versions and paths that drift from the catalog', () {
      final mismatchedVersion = _catalogJson(<Map<String, dynamic>>[
        _validPack()..['version'] = '2.0.0',
      ]);
      final mismatchedPath = _catalogJson(<Map<String, dynamic>>[
        _validPack()
          ..['storagePath'] = 'voice_packs/it/older/chapter_01-v1.zip',
      ]);

      expect(
        () => VoicePack.decodeCatalog(jsonEncode(mismatchedVersion)),
        throwsFormatException,
      );
      expect(
        () => VoicePack.decodeCatalog(jsonEncode(mismatchedPath)),
        throwsFormatException,
      );
    });
  });

  test('VoicePackState copyWith can update and clear an error', () {
    final pack = VoicePack.fromJson(_validPack());
    final failed = VoicePackState(
      pack: pack,
      status: VoicePackDownloadStatus.failed,
      error: 'network',
    );

    final downloading = failed.copyWith(
      status: VoicePackDownloadStatus.downloading,
      progress: 0.5,
      downloadedBytes: 512,
      error: null,
    );

    expect(downloading.status, VoicePackDownloadStatus.downloading);
    expect(downloading.progress, 0.5);
    expect(downloading.downloadedBytes, 512);
    expect(downloading.error, isNull);
    expect(downloading.totalBytes, pack.sizeBytes);
  });
}

Map<String, dynamic> _catalogJson(List<Map<String, dynamic>> packs) {
  return <String, dynamic>{
    'schema': 1,
    'language': 'it-IT',
    'voice': 'it-IT-DiegoNeural',
    'version': '1.0.0',
    'packs': packs,
  };
}

Map<String, dynamic> _validPack({
  String id = 'chapter_01',
  int? chapterId = 1,
  String displayName = 'Capitolo 1',
  String storagePath = 'voice_packs/it/1.0.0/chapter_01-v1.zip',
}) {
  return <String, dynamic>{
    'id': id,
    'chapterId': chapterId,
    'displayName': displayName,
    'version': '1.0.0',
    'questionCount': 2,
    'sizeBytes': 1024,
    'sha256': 'a' * 64,
    'storagePath': storagePath,
    'indexFile': 'index.json',
  };
}
