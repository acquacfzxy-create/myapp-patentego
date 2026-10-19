import 'dart:math' as math;

import 'package:flutter/services.dart';

enum DownloadConnectionType { wifi, ethernet, cellular, offline, unknown }

class DownloadEnvironment {
  const DownloadEnvironment({
    required this.connectionType,
    required this.availableStorageBytes,
  });

  factory DownloadEnvironment.fromMap(Map<Object?, Object?> values) {
    final connection = switch (values['connectionType']) {
      'wifi' => DownloadConnectionType.wifi,
      'ethernet' => DownloadConnectionType.ethernet,
      'cellular' => DownloadConnectionType.cellular,
      'offline' => DownloadConnectionType.offline,
      _ => DownloadConnectionType.unknown,
    };
    final available = values['availableStorageBytes'];
    return DownloadEnvironment(
      connectionType: connection,
      availableStorageBytes: available is num ? available.toInt() : null,
    );
  }

  final DownloadConnectionType connectionType;
  final int? availableStorageBytes;

  bool get isUnmetered =>
      connectionType == DownloadConnectionType.wifi ||
      connectionType == DownloadConnectionType.ethernet;
}

/// Reads only coarse network transport and free app-storage capacity.
/// No device identifiers or network names are collected.
class DownloadPreflightService {
  const DownloadPreflightService();

  static const MethodChannel _channel =
      MethodChannel('com.patentego.app/download_preflight');
  static const int minimumWorkingSpaceBytes = 450 * 1024 * 1024;

  static int requiredStorageBytes(int archiveBytes) {
    // The ZIP and extracted MP3 files coexist during installation. Keep an
    // additional safety margin for the manifest, index and filesystem blocks.
    return math.max(
      minimumWorkingSpaceBytes,
      archiveBytes * 2 + 32 * 1024 * 1024,
    );
  }

  Future<DownloadEnvironment> inspect() async {
    final values = await _channel.invokeMapMethod<Object?, Object?>(
      'getDownloadEnvironment',
    );
    return DownloadEnvironment.fromMap(values ?? const {});
  }
}
