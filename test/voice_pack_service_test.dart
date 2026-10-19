import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lingua_patente/models/voice_pack.dart';
import 'package:lingua_patente/services/voice_pack_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('VoicePackService file safety', () {
    test('recognizes safe relative archive paths', () {
      expect(
        VoicePackService.isSafeArchiveEntryPath('audio/123.mp3'),
        isTrue,
      );
      expect(
        VoicePackService.isSafeArchiveEntryPath('../outside.mp3'),
        isFalse,
      );
      expect(
        VoicePackService.isSafeArchiveEntryPath('/tmp/outside.mp3'),
        isFalse,
      );
      expect(
        VoicePackService.isSafeArchiveEntryPath(r'audio\..\outside.mp3'),
        isFalse,
      );
      expect(
        VoicePackService.isSafeArchiveEntryPath('C:/outside.mp3'),
        isFalse,
      );
    });

    test('accepts safe database question ids and rejects path-like ids', () {
      expect(VoicePackService.isSafeQuestionId('550-0'), isTrue);
      expect(VoicePackService.isSafeQuestionId('12345'), isTrue);
      expect(VoicePackService.isSafeQuestionId('../x'), isFalse);
      expect(VoicePackService.isSafeQuestionId('chapter/1'), isFalse);
      expect(VoicePackService.isSafeQuestionId(r'chapter\1'), isFalse);
      expect(VoicePackService.isSafeQuestionId('question 1'), isFalse);
      expect(VoicePackService.isSafeQuestionId('bad\nvalue'), isFalse);
    });

    test('computes a streaming SHA-256 digest', () async {
      final temp = await Directory.systemTemp.createTemp('voice_pack_sha_');
      addTearDown(() => temp.delete(recursive: true));
      final file = File('${temp.path}/sample.bin');
      await file.writeAsString('abc');

      final digest = await VoicePackService.sha256ForFile(file);

      expect(
        digest,
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      );
    });

    test('extracts a normal zip inside the destination', () async {
      final temp = await Directory.systemTemp.createTemp('voice_pack_zip_');
      addTearDown(() => temp.delete(recursive: true));
      final zipFile = File('${temp.path}/pack.zip');
      final output = Directory('${temp.path}/output');
      await _writeZip(zipFile, <ArchiveFile>[
        ArchiveFile.string('index.json', '{}'),
        ArchiveFile.bytes('audio/1.mp3', <int>[1, 2, 3]),
      ]);

      await VoicePackService.extractZipSafely(
        archiveFile: zipFile,
        destination: output,
        compressedSizeBytes: await zipFile.length(),
        expectedFileCount: 2,
      );

      expect(await File('${output.path}/index.json').exists(), isTrue);
      expect(await File('${output.path}/audio/1.mp3').readAsBytes(), [1, 2, 3]);
    });

    test('rejects zip-slip entries without writing outside', () async {
      final temp = await Directory.systemTemp.createTemp('voice_pack_slip_');
      addTearDown(() => temp.delete(recursive: true));
      final zipFile = File('${temp.path}/pack.zip');
      final output = Directory('${temp.path}/output');
      final escapedFile = File('${temp.path}/escaped.mp3');
      await _writeZip(zipFile, <ArchiveFile>[
        ArchiveFile.bytes('../escaped.mp3', <int>[1, 2, 3]),
      ]);

      await expectLater(
        VoicePackService.extractZipSafely(
          archiveFile: zipFile,
          destination: output,
          compressedSizeBytes: await zipFile.length(),
          expectedFileCount: 1,
        ),
        throwsFormatException,
      );
      expect(await escapedFile.exists(), isFalse);
    });

    test('rejects archives with missing expected files', () async {
      final temp = await Directory.systemTemp.createTemp('voice_pack_count_');
      addTearDown(() => temp.delete(recursive: true));
      final zipFile = File('${temp.path}/pack.zip');
      final output = Directory('${temp.path}/output');
      await _writeZip(zipFile, <ArchiveFile>[
        ArchiveFile.string('index.json', '{}'),
      ]);

      await expectLater(
        VoicePackService.extractZipSafely(
          archiveFile: zipFile,
          destination: output,
          compressedSizeBytes: await zipFile.length(),
          expectedFileCount: 2,
        ),
        throwsFormatException,
      );
    });
  });

  test('restores an installed pack and detects a catalog version update',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final support = await Directory.systemTemp.createTemp('voice_pack_state_');
    addTearDown(() => support.delete(recursive: true));
    final root = Directory('${support.path}/voice_packs/it');
    final installed = Directory('${root.path}/packs/chapter_01/1.0.0');
    await Directory('${installed.path}/audio').create(recursive: true);
    await File('${installed.path}/audio/1.mp3').writeAsBytes(<int>[1]);
    await File('${installed.path}/audio/550-0.mp3').writeAsBytes(<int>[2]);
    await File('${installed.path}/index.json').writeAsString(
      jsonEncode(<String, String>{
        '1': 'audio/1.mp3',
        '550-0': 'audio/550-0.mp3',
      }),
    );
    final manifestFile = File('${root.path}/manifest.json');
    await manifestFile.writeAsString(_manifest('1.0.0'));

    final firstService = VoicePackService(
      supportDirectoryProvider: () async => support,
    );
    await firstService.initialize();
    expect(
      firstService.stateFor('chapter_01')?.status,
      VoicePackDownloadStatus.installed,
    );
    expect(
      firstService.localAudioPath('1'),
      '${installed.path}/audio/1.mp3',
    );
    expect(
      firstService.localAudioPath('550-0'),
      '${installed.path}/audio/550-0.mp3',
    );
    firstService.dispose();

    final restartedService = VoicePackService(
      supportDirectoryProvider: () async => support,
    );
    await restartedService.initialize();
    expect(
      restartedService.stateFor('chapter_01')?.status,
      VoicePackDownloadStatus.installed,
    );
    restartedService.dispose();

    await manifestFile.writeAsString(_manifest('2.0.0'));
    final updatedService = VoicePackService(
      supportDirectoryProvider: () async => support,
    );
    await updatedService.initialize();
    expect(
      updatedService.stateFor('chapter_01')?.status,
      VoicePackDownloadStatus.notDownloaded,
    );
    expect(updatedService.localAudioPath('1'), isNull);
    updatedService.dispose();
  });

  test('restores a partial pack and resumes it with an HTTP range request',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final support = await Directory.systemTemp.createTemp('voice_pack_resume_');
    addTearDown(() => support.delete(recursive: true));

    final archive = Archive()
      ..add(ArchiveFile.string(
        'index.json',
        jsonEncode(<String, String>{
          '1': 'audio/1.mp3',
          '550-0': 'audio/550-0.mp3',
        }),
      ))
      ..add(ArchiveFile.bytes('audio/1.mp3', <int>[1, 2, 3]))
      ..add(ArchiveFile.bytes('audio/550-0.mp3', <int>[4, 5, 6]));
    final archiveBytes = ZipEncoder().encode(archive);
    final checksum = sha256.convert(archiveBytes).toString();

    final root = Directory('${support.path}/voice_packs/it');
    final downloads = Directory('${root.path}/downloads');
    await downloads.create(recursive: true);
    await File('${root.path}/manifest.json').writeAsString(
      _manifestForArchive(
        version: '1.0.0',
        sizeBytes: archiveBytes.length,
        checksum: checksum,
      ),
    );
    final partialLength = archiveBytes.length ~/ 3;
    await File('${downloads.path}/chapter_01-1.0.0.zip.part')
        .writeAsBytes(archiveBytes.sublist(0, partialLength));

    String? receivedRange;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      receivedRange = request.headers.value(HttpHeaders.rangeHeader);
      request.response.statusCode = HttpStatus.partialContent;
      request.response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes $partialLength-${archiveBytes.length - 1}/${archiveBytes.length}',
      );
      request.response.contentLength = archiveBytes.length - partialLength;
      request.response.add(archiveBytes.sublist(partialLength));
      await request.response.close();
    });

    final service = VoicePackService(
      supportDirectoryProvider: () async => support,
      downloadUrlProvider: (_) async => Uri.parse(
        'http://${server.address.address}:${server.port}/chapter_01.zip',
      ),
    );
    addTearDown(service.dispose);
    await service.initialize();

    expect(
      service.stateFor('chapter_01')?.status,
      VoicePackDownloadStatus.paused,
    );
    expect(service.stateFor('chapter_01')?.downloadedBytes, partialLength);

    await service.resume('chapter_01');

    expect(receivedRange, 'bytes=$partialLength-');
    expect(
      service.stateFor('chapter_01')?.status,
      VoicePackDownloadStatus.installed,
    );
    expect(service.localAudioPath('550-0'), isNotNull);
  });
}

String _manifest(String version) {
  return jsonEncode(<String, dynamic>{
    'schema': 1,
    'language': 'it-IT',
    'voice': 'it-IT-DiegoNeural',
    'version': version,
    'packs': <Map<String, dynamic>>[
      <String, dynamic>{
        'id': 'chapter_01',
        'chapterId': 1,
        'displayName': 'Capitolo 1',
        'version': version,
        'questionCount': 2,
        'sizeBytes': 1024,
        'sha256': 'a' * 64,
        'storagePath': 'voice_packs/it/$version/chapter_01.zip',
        'indexFile': 'index.json',
      },
    ],
  });
}

String _manifestForArchive({
  required String version,
  required int sizeBytes,
  required String checksum,
}) {
  return jsonEncode(<String, dynamic>{
    'schema': 1,
    'language': 'it-IT',
    'voice': 'it-IT-Chirp3-HD-Algenib',
    'version': version,
    'packs': <Map<String, dynamic>>[
      <String, dynamic>{
        'id': 'chapter_01',
        'chapterId': 1,
        'displayName': 'Capitolo 1',
        'version': version,
        'questionCount': 2,
        'sizeBytes': sizeBytes,
        'sha256': checksum,
        'storagePath': 'voice_packs/it/$version/chapter_01.zip',
        'indexFile': 'index.json',
      },
    ],
  });
}

Future<void> _writeZip(File file, List<ArchiveFile> entries) async {
  final archive = Archive();
  for (final entry in entries) {
    archive.add(entry);
  }
  final encoded = ZipEncoder().encode(archive);
  await file.writeAsBytes(encoded);
}
