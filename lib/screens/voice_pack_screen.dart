import 'package:flutter/material.dart';

import '../config/app_strings.dart';
import '../config/locale_format.dart';
import '../config/user_error_copy.dart';
import '../config/app_theme.dart';
import '../models/voice_pack.dart';
import '../services/download_preflight_service.dart';
import '../services/voice_pack_service.dart';
import '../widgets/glass_card.dart';

/// Manages the optional chapter voice packs used for offline playback.
class VoicePackScreen extends StatefulWidget {
  const VoicePackScreen({super.key});

  @override
  State<VoicePackScreen> createState() => _VoicePackScreenState();
}

class _VoicePackScreenState extends State<VoicePackScreen> {
  final VoicePackService _service = VoicePackService.instance;
  final DownloadPreflightService _preflightService =
      const DownloadPreflightService();
  bool _isInitializing = true;
  bool _isCheckingDownload = false;
  String? _initializationError;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      await _service.initialize();
    } catch (error) {
      // 只记录「初始化失败」这一事实；原始异常不展示给用户。
      _initializationError = VoicePackService.errorCodeFor(error);
    } finally {
      if (mounted) {
        setState(() => _isInitializing = false);
      }
    }
  }

  Future<void> _retryCatalog() async {
    if (_initializationError != null && mounted) {
      setState(() => _initializationError = null);
    }
    await _service.refreshCatalog();
  }

  String _copy(String key, [Map<String, Object> values = const {}]) {
    var value = AppStrings.get(key);
    for (final entry in values.entries) {
      value = value.replaceAll('{${entry.key}}', '${entry.value}');
    }
    return value;
  }

  String _formatBytes(int bytes) =>
      LocaleFormat.fileSize(AppStrings.getLanguage(), bytes);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(AppStrings.get('voice_pack_title')),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        actions: [
          AnimatedBuilder(
            animation: _service,
            builder: (context, _) => IconButton(
              tooltip: AppStrings.get('voice_pack_retry'),
              onPressed: _service.isCatalogLoading ? null : _retryCatalog,
              icon: const Icon(Icons.refresh),
            ),
          ),
        ],
      ),
      body: Container(
        decoration: AppTheme.pageDecorationFor(context),
        child: AnimatedBuilder(
          animation: _service,
          builder: (context, _) => _buildBody(context),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if ((_isInitializing || _service.isCatalogLoading) &&
        _service.packs.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              AppStrings.get('voice_pack_loading_catalog'),
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.mutedFor(context)),
            ),
          ],
        ),
      );
    }

    final catalogError = _service.catalogError ?? _initializationError;
    if (catalogError != null && _service.packs.isEmpty) {
      return _CatalogMessage(
        icon: Icons.cloud_off_outlined,
        message: AppStrings.get('voice_pack_catalog_error'),
        detail: UserErrorCopy.voicePack(
          catalogError,
          language: AppStrings.getLanguage(),
        ),
        actionLabel: AppStrings.get('voice_pack_retry'),
        onAction: _retryCatalog,
      );
    }

    if (_service.packs.isEmpty) {
      return _CatalogMessage(
        icon: Icons.spatial_audio_off_outlined,
        message: AppStrings.get('voice_pack_empty_catalog'),
        actionLabel: AppStrings.get('voice_pack_retry'),
        onAction: _retryCatalog,
      );
    }

    final installedBytes = _service.packs
        .where((state) => state.status == VoicePackDownloadStatus.installed)
        .fold<int>(0, (sum, state) => sum + state.pack.sizeBytes);

    return RefreshIndicator(
      onRefresh: _retryCatalog,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          GlassCard(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppTheme.primarySoftFor(context),
                        borderRadius: AppTheme.isRetroFor(context)
                            ? BorderRadius.zero
                            : BorderRadius.circular(AppTheme.radiusSm),
                        border: AppTheme.isRetroFor(context)
                            ? Border.all(color: AppTheme.retroLine)
                            : null,
                      ),
                      child: Icon(
                        Icons.record_voice_over_outlined,
                        color: AppTheme.primaryFor(context),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        AppStrings.get('voice_pack_intro'),
                        style: TextStyle(
                          color: AppTheme.inkFor(context),
                          height: 1.45,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  _copy(
                    'voice_pack_total_installed',
                    {'size': _formatBytes(installedBytes)},
                  ),
                  style: TextStyle(
                    color: AppTheme.mutedFor(context),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (_service.catalogError != null) ...[
            const SizedBox(height: 12),
            _InlineCatalogError(
              message: AppStrings.get('voice_pack_catalog_error'),
              onRetry: _retryCatalog,
            ),
          ],
          const SizedBox(height: 16),
          for (final state in _service.packs) ...[
            _VoicePackCard(
              state: state,
              copy: _copy,
              formatBytes: _formatBytes,
              onDownload: () => _prepareDownload(state),
              onPause: () => _service.pause(state.pack.id),
              onResume: () => _prepareDownload(state, resume: true),
              onCancel: () => _service.cancel(state.pack.id),
              onDelete: () => _confirmDelete(context, state),
            ),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }

  Future<void> _prepareDownload(
    VoicePackState state, {
    bool resume = false,
  }) async {
    if (_isCheckingDownload) return;
    setState(() => _isCheckingDownload = true);

    DownloadEnvironment environment;
    try {
      environment = await _preflightService.inspect();
    } catch (_) {
      environment = const DownloadEnvironment(
        connectionType: DownloadConnectionType.unknown,
        availableStorageBytes: null,
      );
    }

    if (!mounted) return;
    final requiredBytes = DownloadPreflightService.requiredStorageBytes(
      state.pack.sizeBytes,
    );
    final availableBytes = environment.availableStorageBytes;

    if (availableBytes != null && availableBytes < requiredBytes) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          icon: Icon(
            Icons.storage_rounded,
            color: AppTheme.warningTextFor(dialogContext),
          ),
          title: Text(AppStrings.get('voice_pack_storage_insufficient_title')),
          content: Text(
            _copy(
              'voice_pack_storage_insufficient_message',
              {
                'available': _formatBytes(availableBytes),
                'required': _formatBytes(requiredBytes),
              },
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(AppStrings.get('voice_pack_ok')),
            ),
          ],
        ),
      );
      if (mounted) setState(() => _isCheckingDownload = false);
      return;
    }

    if (environment.connectionType == DownloadConnectionType.offline) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          icon: Icon(
            Icons.wifi_off_rounded,
            color: AppTheme.warningTextFor(dialogContext),
          ),
          title: Text(AppStrings.get('voice_pack_offline_title')),
          content: Text(AppStrings.get('voice_pack_offline_message')),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(AppStrings.get('voice_pack_ok')),
            ),
          ],
        ),
      );
      if (mounted) setState(() => _isCheckingDownload = false);
      return;
    }

    final isUnmetered = environment.isUnmetered;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: Icon(
          isUnmetered ? Icons.cloud_download_outlined : Icons.sim_card_outlined,
          color: isUnmetered
              ? AppTheme.primaryFor(dialogContext)
              : AppTheme.warningTextFor(dialogContext),
        ),
        title: Text(AppStrings.get('voice_pack_download_confirm_title')),
        content: Text(
          _copy(
            isUnmetered
                ? 'voice_pack_download_confirm_wifi_message'
                : 'voice_pack_download_confirm_mobile_message',
            {
              'size': _formatBytes(state.pack.sizeBytes),
              'required': _formatBytes(requiredBytes),
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(AppStrings.get('voice_pack_cancel')),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            icon: const Icon(Icons.download_rounded),
            label: Text(AppStrings.get('voice_pack_continue_download')),
          ),
        ],
      ),
    );

    if (mounted) setState(() => _isCheckingDownload = false);
    if (confirmed != true) return;
    if (resume) {
      await _service.resume(state.pack.id);
    } else {
      await _service.download(state.pack.id);
    }
  }

  Future<void> _confirmDelete(
    BuildContext context,
    VoicePackState state,
  ) async {
    final packTitle = _localizedPackTitle(state);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(AppStrings.get('voice_pack_delete_confirm_title')),
        content: Text(
          _copy(
            'voice_pack_delete_confirm_message',
            {'name': packTitle},
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(AppStrings.get('voice_pack_cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.dangerFor(dialogContext),
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(AppStrings.get('voice_pack_delete_confirm')),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _service.delete(state.pack.id);
    }
  }

  String _localizedPackTitle(VoicePackState state) {
    if (state.pack.isAllQuestions) {
      return AppStrings.get('voice_pack_all_questions');
    }
    final chapterId = state.pack.chapterId;
    final localizedTitle = chapterId == null
        ? AppStrings.get('voice_pack_uncategorized')
        : _copy('voice_pack_chapter_number', {'chapter': chapterId});
    if (localizedTitle.trim().isNotEmpty) return localizedTitle;

    final manifestTitle = state.pack.displayName.trim();
    return manifestTitle.isNotEmpty
        ? manifestTitle
        : AppStrings.get('voice_pack_uncategorized');
  }
}

class _VoicePackCard extends StatelessWidget {
  const _VoicePackCard({
    required this.state,
    required this.copy,
    required this.formatBytes,
    required this.onDownload,
    required this.onPause,
    required this.onResume,
    required this.onCancel,
    required this.onDelete,
  });

  final VoicePackState state;
  final String Function(String, [Map<String, Object>]) copy;
  final String Function(int) formatBytes;
  final VoidCallback onDownload;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onCancel;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final progress = state.progress.clamp(0.0, 1.0);
    final percent = (progress * 100).round();
    final showsDownloadProgress =
        state.status == VoicePackDownloadStatus.downloading ||
            state.status == VoicePackDownloadStatus.paused;
    final chapterId = state.pack.chapterId;
    final localizedTitle = state.pack.isAllQuestions
        ? AppStrings.get('voice_pack_all_questions')
        : chapterId == null
            ? AppStrings.get('voice_pack_uncategorized')
            : copy('voice_pack_chapter_number', {'chapter': chapterId});
    final title = localizedTitle.trim().isNotEmpty
        ? localizedTitle
        : state.pack.displayName;
    final primaryColor = AppTheme.primaryFor(context);
    final mutedColor = AppTheme.mutedFor(context);
    final metadataStyle = TextStyle(
      color: mutedColor,
      fontSize: 12,
      height: 1.3,
    );
    final isRetro = AppTheme.isRetroFor(context);

    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: AppTheme.inkFor(context),
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        Text(
                          copy(
                            'voice_pack_question_count',
                            {'count': state.pack.questionCount},
                          ),
                          style: metadataStyle,
                        ),
                        Text('•', style: metadataStyle),
                        Text(
                          formatBytes(state.pack.sizeBytes),
                          style: metadataStyle,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _StatusChip(status: state.status),
            ],
          ),
          if (showsDownloadProgress) ...[
            const SizedBox(height: 16),
            LinearProgressIndicator(
              value: progress,
              minHeight: 7,
              borderRadius:
                  isRetro ? BorderRadius.zero : BorderRadius.circular(99),
              backgroundColor: AppTheme.lineFor(context),
              valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                Text(
                  '$percent%',
                  style: TextStyle(
                    color: primaryColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  copy(
                    'voice_pack_downloaded_of',
                    {
                      'downloaded': formatBytes(state.downloadedBytes),
                      'total': formatBytes(state.totalBytes),
                    },
                  ),
                  style: metadataStyle,
                ),
              ],
            ),
          ],
          if (state.status == VoicePackDownloadStatus.failed &&
              state.error != null &&
              state.error!.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              UserErrorCopy.voicePack(
                state.error,
                language: AppStrings.getLanguage(),
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppTheme.dangerFor(context),
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ],
          const SizedBox(height: 14),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: _buildActions(context),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildActions(BuildContext context) {
    switch (state.status) {
      case VoicePackDownloadStatus.notDownloaded:
        return [
          FilledButton.icon(
            onPressed: onDownload,
            icon: const Icon(Icons.download_outlined),
            label: Text(
              AppStrings.get(
                state.pack.isAllQuestions
                    ? 'voice_pack_download_all'
                    : 'voice_pack_download',
              ),
            ),
          ),
        ];
      case VoicePackDownloadStatus.downloading:
        return [
          OutlinedButton.icon(
            onPressed: onCancel,
            icon: const Icon(Icons.close),
            label: Text(AppStrings.get('voice_pack_cancel')),
          ),
          FilledButton.icon(
            onPressed: onPause,
            icon: const Icon(Icons.pause),
            label: Text(AppStrings.get('voice_pack_pause')),
          ),
        ];
      case VoicePackDownloadStatus.paused:
        return [
          OutlinedButton.icon(
            onPressed: onCancel,
            icon: const Icon(Icons.close),
            label: Text(AppStrings.get('voice_pack_cancel')),
          ),
          FilledButton.icon(
            onPressed: onResume,
            icon: const Icon(Icons.play_arrow),
            label: Text(AppStrings.get('voice_pack_resume')),
          ),
        ];
      case VoicePackDownloadStatus.installed:
        return [
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.dangerFor(context),
            ),
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline),
            label: Text(AppStrings.get('voice_pack_delete')),
          ),
        ];
      case VoicePackDownloadStatus.failed:
        return [
          FilledButton.icon(
            onPressed: onDownload,
            icon: const Icon(Icons.refresh),
            label: Text(AppStrings.get('voice_pack_retry')),
          ),
        ];
    }
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final VoicePackDownloadStatus status;

  @override
  Widget build(BuildContext context) {
    final isRetro = AppTheme.isRetroFor(context);
    final (label, color, background) = switch (status) {
      VoicePackDownloadStatus.notDownloaded => (
          AppStrings.get('voice_pack_status_not_downloaded'),
          AppTheme.mutedFor(context),
          AppTheme.lineFor(context).withOpacity(0.55),
        ),
      VoicePackDownloadStatus.downloading => (
          AppStrings.get('voice_pack_status_downloading'),
          AppTheme.primaryFor(context),
          AppTheme.primarySoftFor(context),
        ),
      VoicePackDownloadStatus.paused => (
          AppStrings.get('voice_pack_status_paused'),
          AppTheme.warningTextFor(context),
          AppTheme.warningFor(context).withOpacity(0.1),
        ),
      VoicePackDownloadStatus.installed => (
          AppStrings.get('voice_pack_status_installed'),
          AppTheme.successTextFor(context),
          AppTheme.successSoftFor(context),
        ),
      VoicePackDownloadStatus.failed => (
          AppStrings.get('voice_pack_status_failed'),
          AppTheme.dangerFor(context),
          AppTheme.dangerSoftFor(context),
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: isRetro ? BorderRadius.zero : BorderRadius.circular(99),
        border: isRetro ? Border.all(color: AppTheme.retroLine) : null,
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _InlineCatalogError extends StatelessWidget {
  const _InlineCatalogError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final dangerColor = AppTheme.dangerFor(context);
    final isRetro = AppTheme.isRetroFor(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.dangerSoftFor(context),
        borderRadius: isRetro
            ? BorderRadius.zero
            : BorderRadius.circular(AppTheme.radiusSm),
        border: Border.all(color: dangerColor.withOpacity(0.24)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: dangerColor, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: dangerColor, fontSize: 13),
            ),
          ),
          TextButton(
            onPressed: onRetry,
            child: Text(AppStrings.get('voice_pack_retry')),
          ),
        ],
      ),
    );
  }
}

class _CatalogMessage extends StatelessWidget {
  const _CatalogMessage({
    required this.icon,
    required this.message,
    required this.actionLabel,
    required this.onAction,
    this.detail,
  });

  final IconData icon;
  final String message;
  final String? detail;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(24),
      children: [
        SizedBox(height: MediaQuery.sizeOf(context).height * 0.14),
        Icon(icon, size: 52, color: AppTheme.mutedFor(context)),
        const SizedBox(height: 16),
        Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppTheme.inkFor(context),
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (detail != null && detail!.trim().isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            detail!,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppTheme.mutedFor(context),
              fontSize: 13,
            ),
          ),
        ],
        const SizedBox(height: 20),
        Center(
          child: FilledButton.icon(
            onPressed: onAction,
            icon: const Icon(Icons.refresh),
            label: Text(actionLabel),
          ),
        ),
      ],
    );
  }
}
