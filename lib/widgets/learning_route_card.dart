import 'package:flutter/material.dart';

import '../config/app_theme.dart';

/// 學習路線上的一站（一個章節）。
class LearningRouteStation {
  const LearningRouteStation({
    required this.chapterId,
    required this.title,
    required this.masteredPercent,
    required this.isDone,
    required this.isCurrent,
    required this.isLocked,
  });

  final int chapterId;
  final String title;
  final int masteredPercent;
  final bool isDone;
  final bool isCurrent;
  final bool isLocked;
}

/// 首頁「學習路線」：把章節畫成公路上的站點，當前章節放一輛小車。
///
/// 只負責呈現；站點挑選與文案由調用方準備，避免把資料邏輯放進 UI。
class LearningRouteCard extends StatelessWidget {
  const LearningRouteCard({
    super.key,
    required this.title,
    required this.summary,
    required this.stations,
    required this.stationLabel,
    required this.onStationTap,
  });

  final String title;
  final String summary;
  final List<LearningRouteStation> stations;

  /// 每站副標題，例如「第 3 站 · 已掌握 41%」。
  final String Function(LearningRouteStation station) stationLabel;
  final ValueChanged<LearningRouteStation> onStationTap;

  @override
  Widget build(BuildContext context) {
    final ink = AppTheme.inkFor(context);
    final muted = AppTheme.mutedFor(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 2,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: ink,
                ),
              ),
              Text(
                summary,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: muted,
                ),
              ),
            ],
          ),
        ),
        for (var i = 0; i < stations.length; i++)
          _StationRow(
            station: stations[i],
            label: stationLabel(stations[i]),
            isFirst: i == 0,
            isLast: i == stations.length - 1,
            onTap: () => onStationTap(stations[i]),
          ),
      ],
    );
  }
}

class _StationRow extends StatelessWidget {
  const _StationRow({
    required this.station,
    required this.label,
    required this.isFirst,
    required this.isLast,
    required this.onTap,
  });

  final LearningRouteStation station;
  final String label;
  final bool isFirst;
  final bool isLast;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isRetro = AppTheme.isRetroFor(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ink = AppTheme.inkFor(context);
    final muted = AppTheme.mutedFor(context);
    final primary = AppTheme.primaryFor(context);
    final asphalt = isRetro
        ? AppTheme.retroPrimary
        : isDark
            ? const Color(0xFF3A443E)
            : const Color(0xFF3A3F3B);
    final page = isRetro
        ? AppTheme.retroPage
        : isDark
            ? AppTheme.roadNightPage
            : AppTheme.roadPage;
    final current = station.isCurrent;

    final Widget marker;
    if (current) {
      marker = Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: AppTheme.accentFor(context),
          borderRadius: BorderRadius.circular(isRetro ? 0 : 10),
          border: Border.all(color: AppTheme.roadInk, width: 3),
        ),
        child: Icon(
          Icons.directions_car_filled_rounded,
          size: 24,
          color: AppTheme.onAccentFor(context),
        ),
      );
    } else if (station.isDone) {
      marker = Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: primary,
          shape: isRetro ? BoxShape.rectangle : BoxShape.circle,
          border: Border.all(color: page, width: 3),
        ),
        child: Icon(
          Icons.check_rounded,
          size: 18,
          color: isDark ? AppTheme.roadNightPage : Colors.white,
        ),
      );
    } else {
      marker = Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: page,
          shape: isRetro ? BoxShape.rectangle : BoxShape.circle,
          border: Border.all(color: asphalt, width: 3),
        ),
        child: station.isLocked
            ? Icon(Icons.lock_rounded, size: 16, color: muted)
            : null,
      );
    }

    final texts = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          station.title,
          style: TextStyle(
            fontSize: 15,
            fontWeight: current ? FontWeight.w800 : FontWeight.w700,
            color: ink,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: muted),
        ),
      ],
    );

    return Semantics(
      button: true,
      label: '${station.title}, $label',
      child: ExcludeSemantics(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(isRetro ? 0 : 12),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 52,
                  child: Stack(
                    alignment: Alignment.topCenter,
                    children: [
                      // 路面：第一站從站點中心開始，最後一站停在站點中心。
                      Positioned(
                        top: isFirst ? 28 : 0,
                        bottom: isLast ? null : 0,
                        height: isLast ? (isFirst ? 0 : 28) : null,
                        width: 26,
                        child: Container(color: asphalt),
                      ),
                      Positioned(
                        top: isFirst ? 28 : 0,
                        bottom: isLast ? null : 0,
                        height: isLast ? (isFirst ? 0 : 28) : null,
                        child: CustomPaint(
                          size: const Size(2, double.infinity),
                          painter: _DashPainter(color: page),
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.only(top: current ? 6 : 11),
                        child: marker,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: current
                        ? Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.surfaceFor(context),
                              borderRadius:
                                  BorderRadius.circular(isRetro ? 0 : 12),
                              border: Border.all(
                                color: isRetro ? AppTheme.retroLine : ink,
                                width: 2,
                              ),
                            ),
                            child: texts,
                          )
                        : Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: texts,
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DashPainter extends CustomPainter {
  const _DashPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2;
    const dash = 7.0;
    const gap = 6.0;
    var y = 0.0;
    while (y < size.height) {
      canvas.drawLine(
        Offset(0, y),
        Offset(0, (y + dash).clamp(0, size.height)),
        paint,
      );
      y += dash + gap;
    }
  }

  @override
  bool shouldRepaint(_DashPainter oldDelegate) => oldDelegate.color != color;
}
