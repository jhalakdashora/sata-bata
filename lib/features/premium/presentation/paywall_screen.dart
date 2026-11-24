import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:split_app/app/brand.dart';
import 'package:split_app/app/providers.dart';
import 'package:split_app/features/premium/data/entitlement_repository.dart';
import 'package:split_app/features/premium/domain/pro_feature.dart';

const _proInk = Color(0xFF3B2600);

IconData _featureIcon(ProFeature f) => switch (f) {
  ProFeature.receiptScanning => Icons.document_scanner_rounded,
  ProFeature.itemization => Icons.format_list_bulleted_rounded,
  ProFeature.search => Icons.search_rounded,
  ProFeature.charts => Icons.pie_chart_rounded,
  ProFeature.export => Icons.ios_share_rounded,
  ProFeature.unequalDefaultSplit => Icons.tune_rounded,
  ProFeature.placeholderMembers => Icons.person_add_alt_rounded,
  ProFeature.settleUpReminders => Icons.notifications_active_rounded,
  ProFeature.balanceAlerts => Icons.warning_amber_rounded,
};

class PaywallScreen extends ConsumerStatefulWidget {
  const new({super.key, this.highlight});

  /// `ProFeature.name` that triggered the paywall, shown first.
  final String? highlight;

  @override
  ConsumerState<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends ConsumerState<PaywallScreen> {
  SubscriptionPlan _plan = SubscriptionPlan.yearly;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entitlement = ref.watch(entitlementProvider);
    final features = [...ProFeature.values]
      ..sort(
        (a, b) => (b.name == widget.highlight ? 1 : 0).compareTo(
          a.name == widget.highlight ? 1 : 0,
        ),
      );
    final isPro = entitlement.value?.isPro ?? false;

    return Scaffold(
      appBar: AppBar(title: const Text(Brand.proName)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          // Hero
          DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: const LinearGradient(
                colors: [Color(0xFFFFE3A6), Brand.proColor],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  const Icon(
                    Icons.workspace_premium_rounded,
                    size: 48,
                    color: _proInk,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isPro
                              ? "You're on Pro"
                              : 'Get more out of ${Brand.name}',
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: _proInk,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          isPro
                              ? 'Thanks for supporting us!'
                              : 'Unlock every power feature.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: _proInk.withValues(alpha: 0.8),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          for (final f in features)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: f.name == widget.highlight
                          ? Brand.proColor
                          : Brand.proColor.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      _featureIcon(f),
                      size: 22,
                      color: f.name == widget.highlight
                          ? _proInk
                          : const Color(0xFFB46F0A),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(f.title, style: theme.textTheme.titleSmall),
                          Text(
                            f.description,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
      bottomNavigationBar: isPro
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        for (final p in SubscriptionPlan.values) ...[
                          if (p != SubscriptionPlan.values.first)
                            const SizedBox(width: 10),
                          Expanded(
                            child: _PlanCard(
                              plan: p,
                              selected: _plan == p,
                              badge: p == SubscriptionPlan.yearly
                                  ? 'Save 33%'
                                  : null,
                              onTap: () => setState(() => _plan = p),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: Brand.proColor,
                        foregroundColor: _proInk,
                      ),
                      onPressed: entitlement.isLoading
                          ? null
                          : () async {
                              await ref
                                  .read(entitlementProvider.notifier)
                                  .purchase(_plan);
                              if (context.mounted) context.pop();
                            },
                      child: entitlement.isLoading
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Start Pro (demo purchase)'),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        TextButton(
                          onPressed: () =>
                              ref.read(entitlementProvider.notifier).restore(),
                          child: const Text('Restore purchases'),
                        ),
                        Text(
                          '· Demo: no real payment',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const new({
    required this.plan,
    required this.selected,
    required this.onTap,
    this.badge,
  });

  final SubscriptionPlan plan;
  final bool selected;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: selected
          ? Brand.proColor.withValues(alpha: 0.14)
          : theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: selected ? Brand.proColor : theme.colorScheme.outlineVariant,
          width: selected ? 2 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(plan.label, style: theme.textTheme.titleSmall),
                  const Spacer(),
                  if (badge != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Brand.proColor,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        badge!,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: _proInk,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(plan.priceLabel, style: theme.textTheme.bodyMedium),
            ],
          ),
        ),
      ),
    );
  }
}
