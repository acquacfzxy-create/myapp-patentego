import 'package:flutter_test/flutter_test.dart';
import 'package:lingua_patente/services/download_preflight_service.dart';

void main() {
  group('DownloadEnvironment', () {
    test('parses native connection and storage values', () {
      final environment = DownloadEnvironment.fromMap(const {
        'connectionType': 'wifi',
        'availableStorageBytes': 987654321,
      });

      expect(environment.connectionType, DownloadConnectionType.wifi);
      expect(environment.isUnmetered, isTrue);
      expect(environment.availableStorageBytes, 987654321);
    });

    test('treats cellular and unknown connections as metered', () {
      for (final value in ['cellular', 'something-new']) {
        final environment = DownloadEnvironment.fromMap({
          'connectionType': value,
        });
        expect(environment.isUnmetered, isFalse);
      }
    });

    test('parses offline connection', () {
      final environment = DownloadEnvironment.fromMap(const {
        'connectionType': 'offline',
      });

      expect(environment.connectionType, DownloadConnectionType.offline);
    });
  });

  group('requiredStorageBytes', () {
    test('keeps at least 450 MiB available for the full pack', () {
      const packBytes = 207382884;
      expect(
        DownloadPreflightService.requiredStorageBytes(packBytes),
        DownloadPreflightService.minimumWorkingSpaceBytes,
      );
    });

    test('grows for archives larger than the minimum working space', () {
      const packBytes = 300 * 1024 * 1024;
      expect(
        DownloadPreflightService.requiredStorageBytes(packBytes),
        packBytes * 2 + 32 * 1024 * 1024,
      );
    });
  });
}
