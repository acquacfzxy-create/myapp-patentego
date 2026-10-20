import 'package:flutter/material.dart';

import '../config/app_theme.dart';

/// 道路主題的分段標籤：淺色軌道 + 綠色實底選中項，用於二級頁的頁內切換
/// （錯題回顧、章節選擇）。復古主題與 Web 由調用方沿用原有樣式。
class RoadSegmentedTabs extends StatelessWidget {
  const RoadSegmentedTabs({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = AppTheme.primaryFor(context);
    final onPrimary = isDark ? AppTheme.roadNightPage : Colors.white;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppTheme.lineFor(context).withOpacity(isDark ? 0.6 : 0.55),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: Semantics(
                button: true,
                selected: i == selectedIndex,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onSelected(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    constraints: const BoxConstraints(minHeight: 44),
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: i == selectedIndex ? primary : Colors.transparent,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Text(
                      labels[i],
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: i == selectedIndex
                            ? FontWeight.w800
                            : FontWeight.w600,
                        color: i == selectedIndex
                            ? onPrimary
                            : AppTheme.inkFor(context),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
