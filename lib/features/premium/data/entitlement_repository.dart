import 'package:split_app/features/premium/domain/pro_feature.dart';

/// Billing boundary. Swap [MockEntitlementRepository] for a RevenueCat or
/// store-backed implementation without touching UI code.
abstract interface class EntitlementRepository {
  Future<Entitlement> current();
  Future<Entitlement> purchase(SubscriptionPlan plan);
  Future<Entitlement> restore();

  /// Uses one free scan (no-op for Pro). Returns the updated entitlement.
  Future<Entitlement> consumeFreeScan();
}

enum SubscriptionPlan {
  monthly('Monthly', '₹99 / month'),
  yearly('Yearly', '₹799 / year');

  new(this.label, this.priceLabel);
  final String label;
  final String priceLabel;
}

/// Mock paywall: "purchases" succeed instantly and are kept in memory.
class MockEntitlementRepository implements EntitlementRepository {
  Entitlement _entitlement = const Entitlement.free();

  @override
  Future<Entitlement> current() async => _entitlement;

  @override
  Future<Entitlement> purchase(SubscriptionPlan plan) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    final length = plan == SubscriptionPlan.monthly
        ? const Duration(days: 30)
        : const Duration(days: 365);
    return _entitlement = Entitlement(
      isPro: true,
      expiresAt: DateTime.now().add(length),
      freeScansRemaining: _entitlement.freeScansRemaining,
    );
  }

  @override
  Future<Entitlement> restore() async => _entitlement;

  @override
  Future<Entitlement> consumeFreeScan() async {
    if (_entitlement.isPro || _entitlement.freeScansRemaining == 0) {
      return _entitlement;
    }
    return _entitlement = Entitlement(
      isPro: false,
      freeScansRemaining: _entitlement.freeScansRemaining - 1,
    );
  }

  /// Test/debug helper to drop back to the free tier.
  void reset() => _entitlement = const Entitlement.free();
}
