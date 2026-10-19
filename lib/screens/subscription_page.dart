import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_config.dart';
import '../config/app_strings.dart';
import '../config/user_error_copy.dart';
import '../config/app_theme.dart';
import '../providers/user_state_provider.dart';
import '../services/iap_service.dart';

/// VIP 訂閱引導頁：以商店實際商品資訊完成購買與恢復購買。
class SubscriptionPage extends StatefulWidget {
  const SubscriptionPage({super.key});

  @override
  State<SubscriptionPage> createState() => _SubscriptionPageState();
}

class _SubscriptionPageState extends State<SubscriptionPage>
    with SingleTickerProviderStateMixin {
  static const Color _background = Color(0xFF0B0F14);
  static const Color _surface = Color(0xFF1B2430);
  static const Color _softText = Color(0xFFAAB5C4);
  static const Color _line = Color(0xFF2C3746);

  late final AnimationController _ctaScaleController;
  Animation<double> _ctaScale = const AlwaysStoppedAnimation(1.0);
  late final IapService _iapService;
  late final StreamSubscription<IapVerifiedEvent> _verifiedSubscription;

  bool _isSubscribing = false;
  bool _isRestoring = false;
  bool _isRestoreDialogVisible = false;

  @override
  void initState() {
    super.initState();
    _ctaScaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
      reverseDuration: const Duration(milliseconds: 120),
    );
    _ctaScale = Tween<double>(begin: 1.0, end: 0.97).animate(
      CurvedAnimation(
        parent: _ctaScaleController,
        curve: Curves.easeOut,
        reverseCurve: Curves.easeIn,
      ),
    );

    // IapService 由 main.dart 创建并持有（App 级），页面只使用、不销毁。
    _iapService = Provider.of<IapService>(context, listen: false);
    _iapService.addListener(_handleIapStateChanged);
    _verifiedSubscription =
        _iapService.verifiedPurchases.listen(_handleVerifiedPurchase);
    unawaited(_iapService.loadProducts());
  }

  @override
  void dispose() {
    _iapService.removeListener(_handleIapStateChanged);
    _verifiedSubscription.cancel();
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
        SnackBar(
          content: Text(_purchaseErrorCopy(error)),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _handleVerifiedPurchase(IapVerifiedEvent event) {
    // 仅提示用户在本页刚完成的购买；启动/回前台自动发现的购买不弹窗，
    // 手动恢复的结果由 _handleRestorePurchase 自己反馈。
    if (!mounted || !event.userInitiatedPurchase) return;
    _showSubscriptionSuccessFeedback();
  }

  Future<void> _showSubscriptionSuccessFeedback() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(
          Icons.verified_rounded,
          size: 42,
          color: Color(0xFF16A34A),
        ),
        title: Text(AppStrings.get('sub_subscription_success_title')),
        content: Text(AppStrings.get('sub_subscription_success_message')),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(AppStrings.get('confirm')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 页面是深色底：状态栏需用浅色文字（iOS 读 statusBarBrightness，Android 读 statusBarIconBrightness）。
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarBrightness: Brightness.dark,
        statusBarIconBrightness: Brightness.light,
      ),
      child: _buildPage(context),
    );
  }

  Widget _buildPage(BuildContext context) {
    final isVip = context.watch<UserStateProvider>().isVip;

    return Scaffold(
      backgroundColor: _background,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(context),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 620),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildHeader(isVip: isVip),
                        const SizedBox(height: 24),
                        if (isVip)
                          _buildActiveMembershipPanel(context)
                        else
                          _buildPricingPanel(context),
                        const SizedBox(height: 28),
                        _buildFeatureList(),
                        const SizedBox(height: 26),
                        _buildSubscriptionTimeline(),
                        const SizedBox(height: 22),
                        _buildDisclaimer(),
                        const SizedBox(height: 8),
                        _buildFooterLinks(context),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return SizedBox(
      // 占满宽度：否则 Stack 只有标题宽，关闭按钮会压在标题上。
      width: double.infinity,
      height: 56,
      child: Stack(
        alignment: Alignment.center,
        children: [
          const Text(
            'LinguaPatente',
            style: TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          Positioned.directional(
            textDirection: Directionality.of(context),
            start: 8,
            child: IconButton(
              tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
              icon: const Icon(Icons.close_rounded, color: Colors.white70),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader({required bool isVip}) {
    return Column(
      children: [
        Container(
          width: 64,
          height: 64,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppTheme.premiumGold.withOpacity(0.12),
            border: Border.all(
              color: AppTheme.premiumGold.withOpacity(0.55),
            ),
          ),
          child: const Icon(
            Icons.workspace_premium_rounded,
            size: 34,
            color: AppTheme.premiumGold,
          ),
        ),
        const SizedBox(height: 16),
        // 品牌名保持一行：小屏放大字号时整体缩小，避免在单词中间断行。
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            AppStrings.get('sub_title'),
            textAlign: TextAlign.center,
            maxLines: 1,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          isVip
              ? AppStrings.get('sub_subscription_success_message')
              : AppStrings.get('sub_subtitle'),
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: _softText,
            fontSize: 14,
            height: 1.45,
          ),
        ),
      ],
    );
  }

  Widget _buildPricingPanel(BuildContext context) {
    final product = _iapService.monthlyProduct;
    final error = _iapService.errorMessage;
    final showInlineError = !_iapService.isLoading &&
        error != null &&
        error.isNotEmpty &&
        product == null;
    final inlineErrorMessage = !_iapService.isAvailable
        ? AppStrings.get('iap_unavailable')
        : _iapService.productNotFound
            ? AppStrings.get(_iapService.usesGooglePlayBilling
                ? 'iap_product_unavailable_for_account'
                : 'iap_product_unavailable_for_account_store')
            : AppStrings.get('iap_subscription_not_ready');

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF3C4A5E)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  AppStrings.get('sub_price_main'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.premiumGold,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  AppStrings.get('monthly_subscription').toUpperCase(),
                  style: const TextStyle(
                    color: Color(0xFF171B21),
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (_iapService.isLoading)
            const Align(
              alignment: AlignmentDirectional.centerStart,
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            Text(
              product?.price ?? '--',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.w900,
              ),
            ),
          const SizedBox(height: 4),
          Text(
            AppStrings.get('sub_price_per_day'),
            style: const TextStyle(
              color: _softText,
              fontSize: 12,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 18),
          _buildCtaButton(context),
          if (showInlineError) ...[
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.error_outline_rounded,
                  color: Color(0xFFFCA5A5),
                  size: 17,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    inlineErrorMessage,
                    style: const TextStyle(
                      color: Color(0xFFFCA5A5),
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Text(
            AppStrings.get('sub_price_billing_note'),
            textAlign: TextAlign.center,
            style: const TextStyle(color: _softText, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveMembershipPanel(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF10251E),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF2B7A5B)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                Icons.verified_rounded,
                color: Color(0xFF34D399),
                size: 30,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  AppStrings.get('sub_subscription_success_title'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          if (_iapService.usesStoreBilling) ...[
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: () =>
                  _openExternalUrl(context, _iapService.subscriptionCenterUrl),
              icon: const Icon(Icons.open_in_new_rounded, size: 18),
              label: Text(AppStrings.get(_iapService.usesGooglePlayBilling
                  ? 'manage_subscription_play'
                  : 'manage_subscription')),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Color(0xFF2B7A5B)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFeatureList() {
    return const Column(
      children: [
        _VipFeatureRow(
          icon: Icons.menu_book_rounded,
          titleKey: 'sub_feature_unlimited_practice',
          descKey: 'sub_feature_unlimited_practice_desc',
          color: AppTheme.premiumGold,
        ),
        Divider(height: 1, color: _line, indent: 56),
        _VipFeatureRow(
          icon: Icons.assignment_turned_in_rounded,
          titleKey: 'sub_feature_unlimited_mock',
          descKey: 'sub_feature_unlimited_mock_desc',
          color: Color(0xFF60A5FA),
        ),
        Divider(height: 1, color: _line, indent: 56),
        _VipFeatureRow(
          icon: Icons.fact_check_rounded,
          titleKey: 'sub_feature_unlimited_mistake_review',
          descKey: 'sub_feature_unlimited_mistake_review_desc',
          color: Color(0xFF34D399),
        ),
        SizedBox(height: 16),
        // Shared free benefit, explicitly separated from the VIP benefits.
        _VipFeatureRow(
          icon: Icons.check_circle_outline_rounded,
          titleKey: 'sub_feature_deep_explanations',
          descKey: 'sub_feature_deep_explanations_desc',
          color: Color(0xFF34D399),
        ),
      ],
    );
  }

  Widget _buildSubscriptionTimeline() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _TimelineItem(
            icon: Icons.lock_open_rounded,
            color: AppTheme.premiumGold,
            title: AppStrings.get('sub_timeline_today'),
            subtitle: AppStrings.get('sub_timeline_today_desc'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _TimelineItem(
            icon: Icons.autorenew_rounded,
            color: const Color(0xFF60A5FA),
            title: AppStrings.get('sub_timeline_renewal'),
            subtitle: AppStrings.get('sub_timeline_renewal_desc'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _TimelineItem(
            icon: Icons.event_available_rounded,
            color: const Color(0xFF34D399),
            title: AppStrings.get('sub_timeline_cancel'),
            subtitle: AppStrings.get('sub_timeline_cancel_desc'),
          ),
        ),
      ],
    );
  }

  Widget _buildCtaButton(BuildContext context) {
    final isPurchaseInProgress = _isSubscribing || _iapService.isPurchasing;
    final isDisabled = isPurchaseInProgress || _iapService.isLoading;

    // 最少 52 高，文字换行或字形较高（乌尔都语 Nastaliq、放大字号）时按钮随之变高，避免裁切。
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 52),
      child: ScaleTransition(
        scale: _ctaScale,
        child: FilledButton(
          onPressed: isDisabled ? null : _handleSubscribeButtonPressed,
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            backgroundColor: AppTheme.primary,
            disabledBackgroundColor: const Color(0xFF344154),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: isPurchaseInProgress
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(
                  AppStrings.get('sub_cta_subscribe_button'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildDisclaimer() {
    // Google Play 与 App Store 的取消 / 续订规则不同，按实际结算平台显示。
    return Text(
      AppStrings.get(_iapService.usesGooglePlayBilling
          ? 'sub_disclaimer_text_play'
          : 'sub_disclaimer_text'),
      textAlign: TextAlign.center,
      style: const TextStyle(
        color: Color(0xFF8390A1),
        fontSize: 10,
        height: 1.45,
      ),
    );
  }

  Widget _buildFooterLinks(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      runAlignment: WrapAlignment.center,
      spacing: 2,
      runSpacing: 0,
      children: [
        TextButton(
          onPressed: _iapService.isPurchasing ? null : _handleRestorePurchase,
          child: Text(
            AppStrings.get('restore_purchase'),
            style: const TextStyle(fontSize: 11, color: Color(0xFFBFDBFE)),
          ),
        ),
        if (_iapService.usesStoreBilling)
          TextButton(
            onPressed: () =>
                _openExternalUrl(context, _iapService.subscriptionCenterUrl),
            child: Text(
              AppStrings.get('manage_subscription'),
              style: const TextStyle(fontSize: 11, color: Color(0xFFBFDBFE)),
            ),
          ),
        TextButton(
          onPressed: () =>
              _openExternalUrl(context, AppConfig.termsOfServiceUrl),
          child: Text(
            AppStrings.get('sub_service_terms'),
            style: const TextStyle(fontSize: 11, color: _softText),
          ),
        ),
        TextButton(
          onPressed: () =>
              _openExternalUrl(context, AppConfig.privacyPolicyUrl),
          child: Text(
            AppStrings.get('sub_privacy_policy'),
            style: const TextStyle(fontSize: 11, color: _softText),
          ),
        ),
      ],
    );
  }

  /// 商店错误只显示已本地化的文案；原始 SDK 信息不出现在界面上。
  String _purchaseErrorCopy(Object error) =>
      UserErrorCopy.purchase(error, language: AppStrings.getLanguage());

  Future<void> _handleSubscribe() async {
    try {
      await _iapService.buyMonthly();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_purchaseErrorCopy(e)),
          backgroundColor: Colors.red,
        ),
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

    final blockingMessage = _currentIapBlockingMessage();
    if (blockingMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(blockingMessage), backgroundColor: Colors.red),
      );
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

  String? _currentIapBlockingMessage() {
    if (!_iapService.isAvailable) {
      return AppStrings.get('iap_unavailable');
    }
    if (_iapService.monthlyProduct == null) {
      return AppStrings.get(_iapService.productNotFound
          ? (_iapService.usesGooglePlayBilling
              ? 'iap_product_unavailable_for_account'
              : 'iap_product_unavailable_for_account_store')
          : 'iap_subscription_not_ready');
    }
    return null;
  }

  Future<void> _handleRestorePurchase() async {
    if (!mounted) return;
    setState(() => _isRestoring = true);

    _isRestoreDialogVisible = true;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => Center(
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
          SnackBar(
            content: Text(_purchaseErrorCopy(error)),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      await _dismissRestoreProgressDialog();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_purchaseErrorCopy(e)),
          backgroundColor: Colors.red,
        ),
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

class _VipFeatureRow extends StatelessWidget {
  const _VipFeatureRow({
    required this.icon,
    required this.titleKey,
    required this.descKey,
    required this.color,
  });

  final IconData icon;
  final String titleKey;
  final String descKey;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 21, color: color),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppStrings.get(titleKey),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  AppStrings.get(descKey),
                  style: const TextStyle(
                    color: _SubscriptionPageState._softText,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Icon(
              Icons.check_circle_rounded,
              size: 18,
              color: Color(0xFF34D399),
            ),
          ),
        ],
      ),
    );
  }
}

class _TimelineItem extends StatelessWidget {
  const _TimelineItem({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(height: 8),
        Text(
          title,
          textAlign: TextAlign.center,
          maxLines: 2,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          maxLines: 3,
          style: const TextStyle(
            color: _SubscriptionPageState._softText,
            fontSize: 10,
            height: 1.3,
          ),
        ),
      ],
    );
  }
}
