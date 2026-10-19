import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/voice_pack.dart';

class VoicePackService extends ChangeNotifier {
  VoicePackService({
    FirebaseStorage? storage,
    Future<Directory> Function()? supportDirectoryProvider,
    Future<SharedPreferences> Function()? preferencesProvider,
    Future<Uri> Function(VoicePack pack)? downloadUrlProvider,
    HttpClient Function()? httpClientFactory,
  })  : _storage = storage,
        _supportDirectoryProvider =
            supportDirectoryProvider ?? getApplicationSupportDirectory,
        _preferencesProvider =
            preferencesProvider ?? SharedPreferences.getInstance,
        _downloadUrlProvider = downloadUrlProvider,
        _httpClientFactory = httpClientFactory ?? HttpClient.new;

  static final VoicePackService instance = VoicePackService();

  static const String catalogStoragePath = 'voice_packs/it/manifest.json';
  static const int _catalogMaxBytes = 512 * 1024;
  static const int _indexMaxBytes = 4 * 1024 * 1024;
  static const String _activeVersionPrefix = 'voice_pack.active_version.';

  final FirebaseStorage? _storage;
  final Future<Directory> Function() _supportDirectoryProvider;
  final Future<SharedPreferences> Function() _preferencesProvider;
  final Future<Uri> Function(VoicePack pack)? _downloadUrlProvider;
  final HttpClient Function() _httpClientFactory;

  final Map<String, VoicePackState> _states = <String, VoicePackState>{};
  final Map<String, Map<String, String>> _audioByPack =
      <String, Map<String, String>>{};
  final Map<String, _ActiveVoicePackDownload> _activeDownloads =
      <String, _ActiveVoicePackDownload>{};
  final Map<String, Future<void>> _downloadOperations =
      <String, Future<void>>{};
  final Map<String, int> _operationGeneration = <String, int>{};

  Directory? _rootDirectory;
  SharedPreferences? _preferences;
  Future<void>? _initializeFuture;
  bool _initialized = false;
  bool _isCatalogLoading = false;
  String? _catalogError;

  bool get isCatalogLoading => _isCatalogLoading;
  String? get catalogError => _catalogError;
  List<VoicePackState> get packs =>
      List<VoicePackState>.unmodifiable(_states.values);

  VoicePackState? stateFor(String packId) => _states[packId];

  Future<void> initialize() {
    if (_initialized) return Future<void>.value();
    return _initializeFuture ??= _initialize();
  }

  Future<void> _initialize() async {
    try {
      await _ensureLocalStorage();
      await _loadCachedCatalog();
      await refreshCatalog();
      _initialized = true;
    } finally {
      _initializeFuture = null;
    }
  }

  Future<void> refreshCatalog() async {
    if (_isCatalogLoading) return;
    _isCatalogLoading = true;
    _catalogError = null;
    notifyListeners();

    try {
      await _ensureLocalStorage();
      final data = await (_storage ?? FirebaseStorage.instance)
          .ref(catalogStoragePath)
          .getData(_catalogMaxBytes);
      if (data == null || data.isEmpty) {
        throw const FormatException('Voice pack catalog is empty.');
      }
      final source = utf8.decode(data, allowMalformed: false);
      final catalog = VoicePack.decodeCatalog(source);
      await _writeCatalogCache(source);
      await _reconcileCatalog(catalog);
    } catch (error) {
      _catalogError = errorCodeFor(error);
    } finally {
      _isCatalogLoading = false;
      notifyListeners();
    }
  }

  Future<void> download(String packId) async {
    await initialize();
    final state = _requireState(packId);
    if (state.status == VoicePackDownloadStatus.installed) return;

    final existingOperation = _downloadOperations[packId];
    if (existingOperation != null) {
      if (state.status == VoicePackDownloadStatus.paused) {
        final download = _activeDownloads[packId];
        if (download != null) {
          download.resume();
          _setState(
            state.copyWith(
              status: VoicePackDownloadStatus.downloading,
              error: null,
            ),
          );
        }
      }
      return existingOperation;
    }

    final generation = (_operationGeneration[packId] ?? 0) + 1;
    _operationGeneration[packId] = generation;
    final operation = _performDownload(state.pack, generation);
    _downloadOperations[packId] = operation;
    try {
      await operation;
    } finally {
      if (identical(_downloadOperations[packId], operation)) {
        _downloadOperations.remove(packId);
      }
    }
  }

  Future<void> pause(String packId) async {
    await initialize();
    final download = _activeDownloads[packId];
    final state = _requireState(packId);
    if (download == null ||
        state.status != VoicePackDownloadStatus.downloading) {
      return;
    }
    download.pause();
    _setState(
      state.copyWith(
        status: VoicePackDownloadStatus.paused,
        error: null,
      ),
    );
  }

  Future<void> resume(String packId) async {
    await initialize();
    final state = _requireState(packId);
    final activeDownload = _activeDownloads[packId];
    if (activeDownload != null &&
        state.status == VoicePackDownloadStatus.paused) {
      activeDownload.resume();
      _setState(
        state.copyWith(
          status: VoicePackDownloadStatus.downloading,
          error: null,
        ),
      );
      return;
    }
    if (state.status != VoicePackDownloadStatus.installed) {
      await download(packId);
    }
  }

  Future<void> cancel(String packId) async {
    await initialize();
    final state = _requireState(packId);
    if (state.status == VoicePackDownloadStatus.installed ||
        state.status == VoicePackDownloadStatus.notDownloaded) {
      return;
    }
    _operationGeneration[packId] = (_operationGeneration[packId] ?? 0) + 1;

    final activeDownload = _activeDownloads[packId];
    if (activeDownload != null) await activeDownload.cancel();
    final operation = _downloadOperations[packId];
    if (operation != null) await operation;
    final latestState = _requireState(packId);
    if (latestState.status == VoicePackDownloadStatus.installed) return;
    await _deleteIfExists(_partFile(state.pack));
    _setState(
      latestState.copyWith(
        status: VoicePackDownloadStatus.notDownloaded,
        progress: 0,
        downloadedBytes: 0,
        totalBytes: latestState.pack.sizeBytes,
        error: null,
      ),
    );
  }

  Future<void> delete(String packId) async {
    await initialize();
    final state = _requireState(packId);
    await cancel(packId);

    final root = _requireRootDirectory();
    final packsRoot = Directory(p.join(root.path, 'packs'));
    final packDirectory = Directory(p.join(packsRoot.path, state.pack.id));
    final normalizedPacksRoot = p.normalize(p.absolute(packsRoot.path));
    final normalizedPackPath = p.normalize(p.absolute(packDirectory.path));
    if (!p.isWithin(normalizedPacksRoot, normalizedPackPath) ||
        p.dirname(normalizedPackPath) != normalizedPacksRoot) {
      throw StateError('Refusing to delete an unsafe voice pack path.');
    }
    if (await packDirectory.exists()) {
      await packDirectory.delete(recursive: true);
    }
    await _deleteIfExists(_partFile(state.pack));
    await _preferences?.remove('$_activeVersionPrefix${state.pack.id}');
    _audioByPack.remove(packId);
    _setState(
      state.copyWith(
        status: VoicePackDownloadStatus.notDownloaded,
        progress: 0,
        downloadedBytes: 0,
        totalBytes: state.pack.sizeBytes,
        error: null,
      ),
    );
  }

  String? localAudioPath(String questionId) {
    final normalizedId = questionId.trim();
    if (normalizedId.isEmpty) return null;
    for (final index in _audioByPack.values) {
      final audioPath = index[normalizedId];
      if (audioPath != null) return audioPath;
    }
    return null;
  }

  Future<void> _performDownload(VoicePack pack, int generation) async {
    await _ensureLocalStorage();
    final partFile = _partFile(pack);
    await partFile.parent.create(recursive: true);
    var existingBytes = await partFile.exists() ? await partFile.length() : 0;
    if (existingBytes < 0 || existingBytes > pack.sizeBytes) {
      await _deleteIfExists(partFile);
      existingBytes = 0;
    }
    _setState(
      VoicePackState(
        pack: pack,
        status: VoicePackDownloadStatus.downloading,
        progress: existingBytes / pack.sizeBytes,
        downloadedBytes: existingBytes,
        totalBytes: pack.sizeBytes,
      ),
    );

    try {
      if (existingBytes < pack.sizeBytes) {
        await _downloadArchive(
          pack: pack,
          partFile: partFile,
          generation: generation,
          existingBytes: existingBytes,
        );
      }
      _throwIfNotCurrent(pack.id, generation);
      final fileLength = await partFile.length();
      if (fileLength != pack.sizeBytes) {
        throw const FormatException(
          'Downloaded voice pack size does not match the manifest.',
        );
      }
      final checksum = await sha256ForFile(partFile);
      _throwIfNotCurrent(pack.id, generation);
      if (checksum != pack.sha256) {
        await _deleteIfExists(partFile);
        throw const FormatException(
          'Downloaded voice pack checksum does not match the manifest.',
        );
      }

      final audioIndex = await _installArchive(pack, partFile, generation);
      _throwIfNotCurrent(pack.id, generation);
      _audioByPack[pack.id] = audioIndex;
      await _preferences?.setString(
        '$_activeVersionPrefix${pack.id}',
        pack.version,
      );
      if (pack.isAllQuestions) {
        await _removeRetiredPackDirectories(keepPackId: pack.id);
      }
      await _deleteIfExists(partFile);
      _setState(
        VoicePackState(
          pack: pack,
          status: VoicePackDownloadStatus.installed,
          progress: 1,
          downloadedBytes: pack.sizeBytes,
          totalBytes: pack.sizeBytes,
        ),
      );
    } catch (error) {
      if (_isCurrentOperation(pack.id, generation)) {
        final downloadedBytes =
            await partFile.exists() ? await partFile.length() : 0;
        _setState(
          VoicePackState(
            pack: pack,
            status: VoicePackDownloadStatus.failed,
            progress: downloadedBytes / pack.sizeBytes,
            downloadedBytes: downloadedBytes,
            totalBytes: pack.sizeBytes,
            error: errorCodeFor(error),
          ),
        );
      }
    } finally {
      _activeDownloads.remove(pack.id);
    }
  }

  Future<void> _downloadArchive({
    required VoicePack pack,
    required File partFile,
    required int generation,
    required int existingBytes,
  }) async {
    final uri = await (_downloadUrlProvider?.call(pack) ??
        (_storage ?? FirebaseStorage.instance)
            .ref(pack.storagePath)
            .getDownloadURL()
            .then(Uri.parse));
    _throwIfNotCurrent(pack.id, generation);

    final client = _httpClientFactory();
    final request = await client.getUrl(uri);
    if (existingBytes > 0) {
      request.headers.set(HttpHeaders.rangeHeader, 'bytes=$existingBytes-');
    }
    final response = await request.close();
    _throwIfNotCurrent(pack.id, generation);

    var bytesBeforeResponse = existingBytes;
    FileMode fileMode;
    if (existingBytes > 0 && response.statusCode == HttpStatus.partialContent) {
      final range = response.headers.value(HttpHeaders.contentRangeHeader);
      if (!_validContentRange(range, existingBytes, pack.sizeBytes)) {
        client.close(force: true);
        throw const FormatException(
          'Voice pack server returned an invalid resume range.',
        );
      }
      fileMode = FileMode.append;
    } else if (response.statusCode == HttpStatus.ok) {
      bytesBeforeResponse = 0;
      fileMode = FileMode.write;
    } else {
      client.close(force: true);
      throw HttpException(
        'Voice pack download failed with HTTP ${response.statusCode}.',
        uri: uri,
      );
    }

    final expectedResponseBytes = pack.sizeBytes - bytesBeforeResponse;
    if (response.contentLength >= 0 &&
        response.contentLength != expectedResponseBytes) {
      client.close(force: true);
      throw const FormatException(
        'Voice pack server returned an unexpected file size.',
      );
    }

    final sink = partFile.openWrite(mode: fileMode);
    final completion = Completer<void>();
    var downloadedBytes = bytesBeforeResponse;
    late final StreamSubscription<List<int>> subscription;
    final active = _ActiveVoicePackDownload(
      client: client,
      completion: completion,
      closeSink: () => sink.close(),
    );
    _activeDownloads[pack.id] = active;

    subscription = response.listen(
      (chunk) {
        if (!_isCurrentOperation(pack.id, generation)) return;
        sink.add(chunk);
        downloadedBytes += chunk.length;
        final current = _states[pack.id];
        if (current == null) return;
        _setState(
          current.copyWith(
            progress:
                (downloadedBytes / pack.sizeBytes).clamp(0.0, 1.0).toDouble(),
            downloadedBytes: downloadedBytes,
            totalBytes: pack.sizeBytes,
            error: null,
          ),
        );
      },
      onError: (Object error, StackTrace stackTrace) async {
        await sink.flush();
        await sink.close();
        client.close(force: true);
        if (!completion.isCompleted) {
          completion.completeError(error, stackTrace);
        }
      },
      onDone: () async {
        await sink.flush();
        await sink.close();
        client.close();
        if (!completion.isCompleted) completion.complete();
      },
      cancelOnError: true,
    );
    active.subscription = subscription;
    await completion.future;
  }

  static bool _validContentRange(
    String? value,
    int expectedStart,
    int expectedTotal,
  ) {
    if (value == null) return false;
    final match = RegExp(r'^bytes (\d+)-(\d+)/(\d+)$').firstMatch(value);
    if (match == null) return false;
    final start = int.tryParse(match.group(1)!);
    final end = int.tryParse(match.group(2)!);
    final total = int.tryParse(match.group(3)!);
    return start == expectedStart &&
        total == expectedTotal &&
        end != null &&
        end >= expectedStart &&
        end < expectedTotal;
  }

  Future<Map<String, String>> _installArchive(
    VoicePack pack,
    File archiveFile,
    int generation,
  ) async {
    final packRoot = _packDirectory(pack);
    await packRoot.create(recursive: true);
    final nonce = DateTime.now().microsecondsSinceEpoch;
    final tempDirectory = Directory(
      p.join(packRoot.path, '.${pack.version}.installing.$nonce'),
    );
    final finalDirectory = Directory(p.join(packRoot.path, pack.version));
    Directory? backupDirectory;
    await tempDirectory.create(recursive: true);

    try {
      await extractZipSafely(
        archiveFile: archiveFile,
        destination: tempDirectory,
        compressedSizeBytes: pack.sizeBytes,
        expectedFileCount: pack.questionCount + 1,
      );
      _throwIfNotCurrent(pack.id, generation);
      await _readAudioIndex(pack, tempDirectory);

      if (await finalDirectory.exists()) {
        backupDirectory = Directory(
          p.join(packRoot.path, '.${pack.version}.backup.$nonce'),
        );
        await finalDirectory.rename(backupDirectory.path);
      }
      try {
        await tempDirectory.rename(finalDirectory.path);
      } catch (_) {
        if (backupDirectory != null && await backupDirectory.exists()) {
          await backupDirectory.rename(finalDirectory.path);
        }
        rethrow;
      }

      final installedIndex = await _readAudioIndex(pack, finalDirectory);
      if (backupDirectory != null && await backupDirectory.exists()) {
        await backupDirectory.delete(recursive: true);
      }
      await _removeOldVersions(packRoot, keepVersion: pack.version);
      return installedIndex;
    } catch (_) {
      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
      rethrow;
    }
  }

  Future<void> _loadCachedCatalog() async {
    final cacheFile = _catalogCacheFile;
    if (!await cacheFile.exists()) return;
    try {
      if (await cacheFile.length() > _catalogMaxBytes) {
        throw const FormatException('Cached voice pack catalog is too large.');
      }
      final source = await cacheFile.readAsString();
      await _reconcileCatalog(VoicePack.decodeCatalog(source));
      notifyListeners();
    } catch (error) {
      _catalogError = errorCodeFor(error);
    }
  }

  Future<void> _removeRetiredPackDirectories(
      {required String keepPackId}) async {
    final packsRoot = Directory(
      p.join(_requireRootDirectory().path, 'packs'),
    );
    if (await packsRoot.exists()) {
      await for (final entity in packsRoot.list(followLinks: false)) {
        if (entity is! Directory || p.basename(entity.path) == keepPackId) {
          continue;
        }
        final normalizedRoot = p.normalize(p.absolute(packsRoot.path));
        final normalizedEntity = p.normalize(p.absolute(entity.path));
        if (p.isWithin(normalizedRoot, normalizedEntity) &&
            p.dirname(normalizedEntity) == normalizedRoot) {
          await entity.delete(recursive: true);
        }
      }
    }

    _audioByPack.removeWhere((packId, _) => packId != keepPackId);
    final preferences = _preferences;
    if (preferences != null) {
      final retiredKeys = preferences.getKeys().where(
            (key) =>
                key.startsWith(_activeVersionPrefix) &&
                key != '$_activeVersionPrefix$keepPackId',
          );
      for (final key in retiredKeys.toList(growable: false)) {
        await preferences.remove(key);
      }
    }
  }

  Future<void> _writeCatalogCache(String source) async {
    final cacheFile = _catalogCacheFile;
    final tempFile = File('${cacheFile.path}.tmp');
    await tempFile.writeAsString(source, flush: true);
    try {
      await tempFile.rename(cacheFile.path);
    } on FileSystemException {
      if (await cacheFile.exists()) await cacheFile.delete();
      await tempFile.rename(cacheFile.path);
    }
  }

  Future<void> _reconcileCatalog(List<VoicePack> catalog) async {
    final nextStates = <String, VoicePackState>{};
    final catalogIds = catalog.map((pack) => pack.id).toSet();
    _audioByPack.removeWhere((packId, _) => !catalogIds.contains(packId));

    for (final pack in catalog) {
      final current = _states[pack.id];
      final hasActiveDownload = current != null &&
          current.pack.version == pack.version &&
          (current.status == VoicePackDownloadStatus.downloading ||
              current.status == VoicePackDownloadStatus.paused);
      if (hasActiveDownload) {
        nextStates[pack.id] = current.copyWith(pack: pack);
        continue;
      }
      nextStates[pack.id] = await _restoredState(pack);
    }
    _states
      ..clear()
      ..addAll(nextStates);
  }

  Future<VoicePackState> _restoredState(VoicePack pack) async {
    final versionDirectory = Directory(
      p.join(_packDirectory(pack).path, pack.version),
    );
    if (!await versionDirectory.exists()) {
      _audioByPack.remove(pack.id);
      final storedVersion =
          _preferences?.getString('$_activeVersionPrefix${pack.id}');
      if (storedVersion != null && storedVersion != pack.version) {
        await _preferences?.remove('$_activeVersionPrefix${pack.id}');
      }
      final partFile = _partFile(pack);
      if (await partFile.exists()) {
        final downloadedBytes = await partFile.length();
        if (downloadedBytes > 0 && downloadedBytes <= pack.sizeBytes) {
          return VoicePackState(
            pack: pack,
            status: VoicePackDownloadStatus.paused,
            progress: downloadedBytes / pack.sizeBytes,
            downloadedBytes: downloadedBytes,
            totalBytes: pack.sizeBytes,
          );
        }
        await _deleteIfExists(partFile);
      }
      return VoicePackState(pack: pack);
    }

    try {
      final index = await _readAudioIndex(pack, versionDirectory);
      _audioByPack[pack.id] = index;
      await _preferences?.setString(
        '$_activeVersionPrefix${pack.id}',
        pack.version,
      );
      return VoicePackState(
        pack: pack,
        status: VoicePackDownloadStatus.installed,
        progress: 1,
        downloadedBytes: pack.sizeBytes,
        totalBytes: pack.sizeBytes,
      );
    } catch (error) {
      _audioByPack.remove(pack.id);
      return VoicePackState(
        pack: pack,
        status: VoicePackDownloadStatus.failed,
        totalBytes: pack.sizeBytes,
        error: errorCodeFor(error),
      );
    }
  }

  Future<Map<String, String>> _readAudioIndex(
    VoicePack pack,
    Directory versionDirectory,
  ) async {
    final indexPath =
        p.normalize(p.join(versionDirectory.path, pack.indexFile));
    final rootPath = p.normalize(p.absolute(versionDirectory.path));
    final absoluteIndexPath = p.normalize(p.absolute(indexPath));
    if (!p.isWithin(rootPath, absoluteIndexPath)) {
      throw const FormatException('Voice pack index path escapes its pack.');
    }
    final indexFile = File(absoluteIndexPath);
    if (!await indexFile.exists() ||
        await indexFile.length() > _indexMaxBytes) {
      throw const FormatException('Voice pack index is missing or too large.');
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(await indexFile.readAsString());
    } on FormatException {
      throw const FormatException('Voice pack index is not valid JSON.');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Voice pack index must be an object.');
    }
    if (decoded.length != pack.questionCount) {
      throw const FormatException(
        'Voice pack index count does not match the manifest.',
      );
    }

    final result = <String, String>{};
    for (final entry in decoded.entries) {
      final questionId = entry.key;
      final relativeAudioPath = entry.value;
      if (!isSafeQuestionId(questionId) ||
          relativeAudioPath is! String ||
          !isSafeArchiveEntryPath(relativeAudioPath) ||
          !relativeAudioPath.toLowerCase().endsWith('.mp3')) {
        throw const FormatException('Voice pack index entry is invalid.');
      }
      final audioPath = p.normalize(
        p.absolute(p.join(versionDirectory.path, relativeAudioPath)),
      );
      if (!p.isWithin(rootPath, audioPath) ||
          await FileSystemEntity.type(audioPath, followLinks: false) !=
              FileSystemEntityType.file) {
        throw const FormatException(
          'Voice pack index references a missing audio file.',
        );
      }
      result[questionId] = audioPath;
    }
    return Map<String, String>.unmodifiable(result);
  }

  Future<void> _ensureLocalStorage() async {
    if (_rootDirectory == null) {
      final supportDirectory = await _supportDirectoryProvider();
      _rootDirectory = Directory(
        p.join(supportDirectory.path, 'voice_packs', 'it'),
      );
      await _rootDirectory!.create(recursive: true);
    }
    _preferences ??= await _preferencesProvider();
  }

  Future<void> _removeOldVersions(
    Directory packRoot, {
    required String keepVersion,
  }) async {
    await for (final entity in packRoot.list(followLinks: false)) {
      if (entity is! Directory || p.basename(entity.path) == keepVersion) {
        continue;
      }
      final parent = p.normalize(p.absolute(p.dirname(entity.path)));
      if (parent == p.normalize(p.absolute(packRoot.path))) {
        await entity.delete(recursive: true);
      }
    }
  }

  VoicePackState _requireState(String packId) {
    final state = _states[packId];
    if (state == null) {
      throw ArgumentError.value(packId, 'packId', 'Unknown voice pack.');
    }
    return state;
  }

  void _setState(VoicePackState state) {
    _states[state.pack.id] = state;
    notifyListeners();
  }

  bool _isCurrentOperation(String packId, int generation) {
    return _operationGeneration[packId] == generation;
  }

  void _throwIfNotCurrent(String packId, int generation) {
    if (!_isCurrentOperation(packId, generation)) {
      throw const _VoicePackCancelled();
    }
  }

  Directory _packDirectory(VoicePack pack) {
    return Directory(p.join(_requireRootDirectory().path, 'packs', pack.id));
  }

  File _partFile(VoicePack pack) {
    return File(
      p.join(
        _requireRootDirectory().path,
        'downloads',
        '${pack.id}-${pack.version}.zip.part',
      ),
    );
  }

  File get _catalogCacheFile =>
      File(p.join(_requireRootDirectory().path, 'manifest.json'));

  Directory _requireRootDirectory() {
    final directory = _rootDirectory;
    if (directory == null) {
      throw StateError('VoicePackService has not been initialized.');
    }
    return directory;
  }

  static Future<void> _deleteIfExists(File file) async {
    if (await file.exists()) await file.delete();
  }

  static Future<String> sha256ForFile(File file) async {
    return (await sha256.bind(file.openRead()).first).toString();
  }

  static bool isSafeArchiveEntryPath(String value) {
    if (value.isEmpty ||
        value.startsWith('/') ||
        value.startsWith(r'\') ||
        value.contains(r'\') ||
        RegExp(r'^[A-Za-z]:').hasMatch(value)) {
      return false;
    }
    final segments = value.split('/');
    return segments.every(
      (segment) => segment.isNotEmpty && segment != '.' && segment != '..',
    );
  }

  static bool isSafeQuestionId(String value) {
    return RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$').hasMatch(value);
  }

  static Future<void> extractZipSafely({
    required File archiveFile,
    required Directory destination,
    required int compressedSizeBytes,
    required int expectedFileCount,
  }) async {
    final input = InputFileStream(archiveFile.path);
    Archive? archive;
    try {
      archive = ZipDecoder().decodeStream(input, verify: true);
      final destinationPath = p.normalize(p.absolute(destination.path));
      final seenPaths = <String>{};
      var uncompressedBytes = 0;
      var fileCount = 0;
      final maxUncompressedBytes = math.max(
        compressedSizeBytes * 20,
        64 * 1024 * 1024,
      );
      final maxEntries = math.max(expectedFileCount * 2, 64);

      for (final entry in archive) {
        var entryName = entry.name;
        final isDirectory = entry.isDirectory;
        if (isDirectory && entryName.endsWith('/')) {
          entryName = entryName.substring(0, entryName.length - 1);
        }
        if (!isSafeArchiveEntryPath(entryName) || entry.isSymbolicLink) {
          throw const FormatException('Voice pack archive path is unsafe.');
        }
        final outputPath = p.normalize(
          p.absolute(p.join(destinationPath, entryName)),
        );
        if (!p.isWithin(destinationPath, outputPath) ||
            !seenPaths.add(outputPath)) {
          throw const FormatException(
            'Voice pack archive contains an unsafe or duplicate path.',
          );
        }

        if (isDirectory) {
          await Directory(outputPath).create(recursive: true);
          continue;
        }
        fileCount += 1;
        uncompressedBytes += entry.size;
        if (entry.size < 0 ||
            fileCount > maxEntries ||
            uncompressedBytes > maxUncompressedBytes) {
          throw const FormatException(
              'Voice pack archive is unreasonably large.');
        }
        await Directory(p.dirname(outputPath)).create(recursive: true);
        final output = OutputFileStream(outputPath);
        try {
          entry.writeContent(output);
        } finally {
          await output.close();
        }
      }
      if (fileCount != expectedFileCount) {
        throw const FormatException(
          'Voice pack archive file count does not match the manifest.',
        );
      }
    } finally {
      if (archive != null) await archive.clear();
      await input.close();
    }
  }

  /// 把异常归类为稳定的错误码（即界面文案 key，由 UserErrorCopy.voicePack 本地化）。
  ///
  /// 不保存原始异常文字：Storage / HTTP 错误信息可能包含带令牌的下载地址。
  /// debug 构建只记录异常类型与错误码。
  static String errorCodeFor(Object error) {
    final String code;
    var detail = '-';
    if (error is _VoicePackCancelled) {
      code = 'voice_pack_error_cancelled';
    } else if (error is FirebaseException) {
      detail = error.code;
      code = switch (error.code) {
        'canceled' => 'voice_pack_error_cancelled',
        'retry-limit-exceeded' ||
        'network-request-failed' =>
          'voice_pack_error_network',
        'invalid-checksum' ||
        'server-file-wrong-size' =>
          'voice_pack_error_corrupted',
        'object-not-found' ||
        'bucket-not-found' ||
        'project-not-found' ||
        'quota-exceeded' ||
        'unauthenticated' ||
        'unauthorized' =>
          'voice_pack_error_unavailable',
        _ => 'voice_pack_error_generic',
      };
    } else if (error is SocketException ||
        error is TimeoutException ||
        error is HandshakeException) {
      code = 'voice_pack_error_network';
    } else if (error is HttpException) {
      // 服务端返回非 2xx（例如资源不存在或暂时不可用）。
      code = 'voice_pack_error_unavailable';
    } else if (error is FormatException) {
      code = 'voice_pack_error_corrupted';
    } else if (error is FileSystemException) {
      final errno = error.osError?.errorCode;
      detail = '$errno';
      // ENOSPC：Linux/Android 为 28，Darwin/iOS 同为 28。
      code = errno == 28
          ? 'voice_pack_error_storage_full'
          : 'voice_pack_error_storage';
    } else {
      code = 'voice_pack_error_generic';
    }
    if (kDebugMode) {
      debugPrint('[voice_pack] ${error.runtimeType} code=$detail -> $code');
    }
    return code;
  }

  @override
  void dispose() {
    for (final download in _activeDownloads.values) {
      unawaited(download.cancel());
    }
    _activeDownloads.clear();
    super.dispose();
  }
}

class _ActiveVoicePackDownload {
  _ActiveVoicePackDownload({
    required this.client,
    required this.completion,
    required this.closeSink,
  });

  final HttpClient client;
  final Completer<void> completion;
  final Future<void> Function() closeSink;
  StreamSubscription<List<int>>? subscription;
  bool _closed = false;

  void pause() => subscription?.pause();

  void resume() => subscription?.resume();

  Future<void> cancel() async {
    if (_closed) return;
    _closed = true;
    await subscription?.cancel();
    await closeSink();
    client.close(force: true);
    if (!completion.isCompleted) {
      completion.completeError(const _VoicePackCancelled());
    }
  }
}

class _VoicePackCancelled implements Exception {
  const _VoicePackCancelled();
}
