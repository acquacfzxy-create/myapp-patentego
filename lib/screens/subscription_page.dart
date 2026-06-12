import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_strings.dart';
import '../config/app_config.dart';
import '../providers/user_state_provider.dart';
import '../services/iap_service.dart';

/// 訂閱頁面（Premium 升級）
/// 視覺完全對齊設計稿 + 綁定業務邏輯
class SubscriptionPage extends StatefulWidget {
  const SubscriptionPage({super.key});

  @override
  State<SubscriptionPage> createState() => _SubscriptionPageState();
}

class _SubscriptionPageState extends State<SubscriptionPage>
    with TickerProviderStateMixin {
  late final AnimationController _sparkleController;

  late final AnimationController _confettiController;
  late final AnimationController _ctaScaleController;
  Animation<double> _ctaScale = const AlwaysStoppedAnimation(1.0);

  bool _showConfetti = false;
  bool _isSubscribing = false;
  bool _isRestoring = false;
  bool _isRestoreDialogVisible = false;
  late final IapService _iapService;

  @override
  void initState() {
    super.initState();

    _sparkleController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);

    _ctaScaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
      reverseDuration: const Duration(milliseconds: 120),
    );
    _ctaScale = Tween<double>(begin: 1.0, end: 0.96).animate(
      CurvedAnimation(
        parent: _ctaScaleController,
        curve: Curves.easeOut,
        reverseCurve: Curves.easeIn,
      ),
    );

    _confettiController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed && mounted) {
          setState(() {
            _showConfetti = false;
          });
          _confettiController.reset();
        }
      });

    final iapService = IapService();
    _iapService = iapService;
    _iapService
      ..addListener(_handleIapStateChanged)
      ..init(onEntitlementActive: _activateVipFromPurchase);
  }

  @override
  void dispose() {
    _iapService
      ..removeListener(_handleIapStateChanged)
      ..dispose();
    _sparkleController.dispose();
    _confettiController.dispose();
    _ctaScaleController.dispose();
    super.dispose();
  }

  void _handleIapStateChanged() {
    if (!mounted) return;
    final wasUserOperationActive = _isSubscribing || _isRestoring;
    setState(() {
      _isSubscribing = _iapService.isBuying;
      _isRestoring = _iapService.isRestoring;
    });

    final error = _iapService.errorMessage;
    if (error != null && error.isNotEmpty && wasUserOperationActive) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _activateVipFromPurchase() async {
    final userStateProvider =
        Provider.of<UserStateProvider>(context, listen: false);
    await userStateProvider.activateVipFromVerifiedPurchase();

    if (!mounted) return;
    if (_isRestoring) {
      return;
    }

    await _showSubscriptionSuccessFeedback();
  }

  Future<void> _showSubscriptionSuccessFeedback() async {
    if (!mounted) return;
    setState(() {
      _showConfetti = true;
    });
    _confettiController.forward(from: 0);

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(AppStrings.get('sub_subscription_success_title')),
          content: Text(AppStrings.get('sub_subscription_success_message')),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(AppStrings.get('confirm')),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.topCenter,
            radius: 1.2,
            colors: [
              Color(0xFF1E1B4B), // 深紫
              Color(0xFF0F172A), // 深藍
            ],
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              SingleChildScrollView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _buildHeader(context),
                    const SizedBox(height: 20),
                    _buildFeatureList(context),
                    const SizedBox(height: 24),
                    _buildPricingCard(context),
                    const SizedBox(height: 16),
                    _buildCtaButton(context),
                    const SizedBox(height: 12),
                    _buildDisclaimer(context),
                    const SizedBox(height: 12),
                    _buildFooterLinks(context),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
              if (_showConfetti)
                Positioned.fill(
                  child: IgnorePointer(
                    child: AnimatedBuilder(
                      animation: _confettiController,
                      builder: (context, _) {
                        return CustomPaint(
                          painter: _ConfettiPainter(
                              progress: _confettiController.value),
                        );
                      },
                    ),
                  ),
                ),
              // 右上角返回按鈕
              Positioned.directional(
                textDirection: Directionality.of(context),
                top: 8,
                start: 8,
                child: IconButton(
                  icon: const Icon(
                    Icons.close,
                    color: Colors.white70,
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Column(
      children: [
        // 金色皇冠
        Container(
          margin: const EdgeInsets.only(top: 16, bottom: 12),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFACC15).withOpacity(0.6),
                blurRadius: 24,
                spreadRadius: 2,
              ),
            ],
          ),
          child: const Icon(
            Icons.workspace_premium,
            size: 64,
            color: Color(0xFFFACC15),
          ),
        ),
        // 標題
        Text(
          AppStrings.get('sub_title'),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          AppStrings.get('sub_subtitle'),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 13,
            color: Color(0xFFBFDBFE),
          ),
        ),
      ],
    );
  }

  static const double _iconBoxSize = 36.0;
  static const double _iconBoxRadius = 8.0;
  static const Color _iconGold = Color(0xFFF59E0B);

  Widget _buildFeatureList(BuildContext context) {
    return Column(
      children: [
        _buildFeatureRow(
          icon: Icons.library_books,
          titleKey: 'sub_feature_unlimited_practice',
          descKey: 'sub_feature_unlimited_practice_desc',
          hasGlow: false,
        ),
        _buildFeatureRow(
          icon: Icons.assignment_turned_in,
          titleKey: 'sub_feature_unlimited_mock',
          descKey: 'sub_feature_unlimited_mock_desc',
          hasGlow: false,
        ),
        _buildFeatureRow(
          icon: Icons.auto_fix_high,
          titleKey: 'sub_feature_unlimited_mistake_review',
          descKey: 'sub_feature_unlimited_mistake_review_desc',
          hasGlow: false,
        ),
        _buildFeatureRow(
          icon: Icons.auto_awesome,
          titleKey: 'sub_feature_deep_explanations',
          descKey: 'sub_feature_deep_explanations_desc',
          hasGlow: true,
        ),
        _buildFeatureRow(
          icon: Icons.insights,
          titleKey: 'sub_feature_study_center',
          descKey: 'sub_feature_study_center_desc',
          hasGlow: false,
        ),
        _buildFeatureRow(
          icon: Icons.cloud_sync,
          titleKey: 'sub_feature_cloud_sync',
          descKey: 'sub_feature_cloud_sync_desc',
          hasGlow: false,
        ),
      ],
    );
  }

  Widget _buildFeatureRow({
    required IconData icon,
    required String titleKey,
    required String descKey,
    Widget? trailing,
    bool hasGlow = false,
  }) {
    final title = AppStrings.get(titleKey);
    final desc = AppStrings.get(descKey);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _buildIconContainer(icon: icon, hasGlow: hasGlow),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                if (desc.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    desc,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.normal,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  Widget _buildIconContainer({required IconData icon, bool hasGlow = false}) {
    return Container(
      width: _iconBoxSize,
      height: _iconBoxSize,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _iconGold.withOpacity(0.15),
        borderRadius: BorderRadius.circular(_iconBoxRadius),
        boxShadow: hasGlow
            ? [
                BoxShadow(
                  color: _iconGold.withOpacity(0.4),
                  blurRadius: 10,
                  spreadRadius: 0,
                ),
              ]
            : null,
      ),
      child: Icon(
        icon,
        size: 20,
        color: _iconGold,
      ),
    );
  }

  Widget _buildPricingCard(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: Colors.white.withOpacity(0.06),
            border: Border.all(
              color: Colors.white.withOpacity(0.18),
              width: 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Align(
                alignment: Alignment.topRight,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFACC15),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    AppStrings.get('monthly_subscription').toUpperCase(),
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _iapService.monthlyProduct == null
                    ? AppStrings.get('sub_price_main')
                    : '${_iapService.monthlyProduct!.price} / ${AppStrings.get('monthly_subscription')}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                AppStrings.get('sub_price_per_day'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFFBFDBFE),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                AppStrings.get('sub_price_billing_note'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF9CA3AF),
                ),
              ),
              const SizedBox(height: 16),
              _buildSubscriptionTimeline(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSubscriptionTimeline() {
    return Column(
      children: [
        // dots + line
        SizedBox(
          // 給時間軸更充足的垂直空間，避免文字在小機型上被擠出容器
          height: 52,
          child: Stack(
            alignment: Alignment.topCenter,
            children: [
              Positioned(
                top: 8,
                left: 0,
                right: 0,
                child: Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: 2,
                        color: const Color(0xFF3B82F6),
                      ),
                    ),
                    Expanded(
                      child: Container(
                        height: 2,
                        color: Colors.white.withOpacity(0.25),
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildTimelineDot(
                    color: const Color(0xFF3B82F6),
                    titleKey: 'sub_timeline_today',
                    subtitleKey: 'sub_timeline_today_desc',
                  ),
                  _buildTimelineDot(
                    color: const Color(0xFF60A5FA),
                    titleKey: 'sub_timeline_renewal',
                    subtitleKey: 'sub_timeline_renewal_desc',
                  ),
                  _buildTimelineDot(
                    color: const Color(0xFFFACC15),
                    titleKey: 'sub_timeline_cancel',
                    subtitleKey: 'sub_timeline_cancel_desc',
                    multiLineSubtitle: true,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTimelineDot({
    required Color color,
    required String titleKey,
    required String subtitleKey,
    bool multiLineSubtitle = false,
  }) {
    final subtitle = AppStrings.get(subtitleKey);
    return Column(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            border: Border.all(
              color: const Color(0xFF020617),
              width: 2,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          AppStrings.get(titleKey),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        if (subtitle.isNotEmpty) ...[
          const SizedBox(height: 1),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 9,
              color: Color(0xFF9CA3AF),
            ),
            maxLines: multiLineSubtitle ? 2 : 1,
          ),
        ],
      ],
    );
  }

  Widget _buildCtaButton(BuildContext context) {
    final isPurchaseInProgress = _isSubscribing || _iapService.isPurchasing;
    final isDisabled = isPurchaseInProgress ||
        _iapService.isLoading ||
        !_iapService.isAvailable ||
        _iapService.monthlyProduct == null;
    return SizedBox(
      width: double.infinity,
      child: ScaleTransition(
        scale: _ctaScale,
        child: ElevatedButton(
          onPressed: isDisabled ? null : _handleSubscribeButtonPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF2563EB),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            elevation: 8,
            shadowColor: const Color(0xFF3B82F6).withOpacity(0.6),
          ),
          child: isPurchaseInProgress
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(
                  _iapService.isLoading
                      ? AppStrings.get('sub_restore_checking')
                      : AppStrings.get('sub_cta_subscribe_button'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildDisclaimer(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Text(
        AppStrings.get('sub_disclaimer_text'),
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 10,
          height: 1.4,
          color: Colors.white60,
        ),
      ),
    );
  }

  Widget _buildFooterLinks(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      runAlignment: WrapAlignment.center,
      spacing: 4,
      runSpacing: 0,
      children: [
        TextButton(
          onPressed: _iapService.isPurchasing ? null : _handleRestorePurchase,
          child: Text(
            AppStrings.get('restore_purchase'),
            style: const TextStyle(fontSize: 11, color: Color(0xFFBFDBFE)),
          ),
        ),
        TextButton(
          onPressed: () =>
              _openExternalUrl(context, AppConfig.termsOfServiceUrl),
          child: Text(
            AppStrings.get('sub_service_terms'),
            style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
          ),
        ),
        TextButton(
          onPressed: () =>
              _openExternalUrl(context, AppConfig.privacyPolicyUrl),
          child: Text(
            AppStrings.get('sub_privacy_policy'),
            style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
          ),
        ),
      ],
    );
  }

  Future<void> _handleSubscribe() async {
    try {
      await _iapService.buyMonthly();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
      );
      if (mounted) {
        setState(() {
          _isSubscribing = false;
        });
      }
    }
  }

  Future<void> _handleSubscribeButtonPressed() async {
    if (_isSubscribing || _iapService.isPurchasing) {
      return;
    }

    setState(() {
      _isSubscribing = true;
    });

    await _ctaScaleController.forward();
    await _ctaScaleController.reverse();
    if (mounted) {
      await _handleSubscribe();
    }
  }

  Future<void> _handleRestorePurchase() async {
    if (!mounted) return;
    setState(() => _isRestoring = true);

    _isRestoreDialogVisible = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Center(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(AppStrings.get('sub_restore_checking')),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      final restored = await _iapService.restorePurchases();
      if (!mounted) return;
      await _dismissRestoreProgressDialog();
      if (!mounted) return;

      if (restored) {
        await _showSubscriptionSuccessFeedback();
        return;
      }

      final error = _iapService.errorMessage;
      if (error == null || error.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppStrings.get('sub_restore_not_found'))),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      if (!mounted) return;
      await _dismissRestoreProgressDialog();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) {
        setState(() => _isRestoring = false);
      }
    }
  }

  Future<void> _dismissRestoreProgressDialog() async {
    if (!_isRestoreDialogVisible || !mounted) return;
    _isRestoreDialogVisible = false;
    Navigator.of(context, rootNavigator: true).pop();
    await Future<void>.delayed(Duration.zero);
  }

  Future<void> _openExternalUrl(BuildContext context, String url) async {
    final uri = Uri.parse(url);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.get('open_link_failed'))),
      );
    }
  }
}

/// 簡單的五彩紙屑動畫繪製器（噴發效果）
class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter({required this.progress}) {
    _random ??= Random();
  }

  final double progress;
  static Random? _random;

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = _random!;
    const count = 80;

    for (var i = 0; i < count; i++) {
      final t = i / count;
      final angle = t * 2 * pi;
      final radius = size.width * 0.2 * (0.5 + rnd.nextDouble());

      final dx = size.width / 2 +
          radius * cos(angle) * (1.0 - progress) +
          (rnd.nextDouble() - 0.5) * 40;
      final dy = size.height * progress +
          (rnd.nextDouble() - 0.5) * 60 * (1.0 - progress);

      final color = Colors.primaries[i % Colors.primaries.length]
          .withOpacity(0.8 - progress * 0.5);
      final paint = Paint()..color = color;

      final sz = 4.0 + rnd.nextDouble() * 4.0;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(dx, dy), width: sz, height: sz * 1.6),
          const Radius.circular(2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
