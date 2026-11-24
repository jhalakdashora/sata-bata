import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:split_app/features/auth/data/auth_repository.dart';
import 'package:split_app/features/ledger/data/in_memory_ledger_repository.dart';
import 'package:split_app/features/ledger/data/ledger_repository.dart';
import 'package:split_app/features/premium/data/entitlement_repository.dart';
import 'package:split_app/features/premium/domain/pro_feature.dart';
import 'package:split_app/features/receipts/data/receipt_scanner.dart';

/// Overridden in main() with Supabase implementations when configured.
final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => DemoAuthRepository(),
);

final ledgerRepositoryProvider = Provider<LedgerRepository>(
  (ref) => InMemoryLedgerRepository(),
);

/// Live ledger. On first listen it also generates any recurring expenses
/// that became due while the app was closed.
/// Emits the current sign-in state, then every change.
final signedInProvider = StreamProvider<bool>((ref) async* {
  final auth = ref.watch(authRepositoryProvider);
  yield auth.isSignedIn;
  yield* auth.signedInChanges;
});

final ledgerProvider = StreamProvider<LedgerSnapshot>((ref) {
  // Rebuild (and refetch) whenever the user signs in or out, so one user's
  // data never leaks into another session.
  final signedIn = ref.watch(signedInProvider).value ?? false;
  if (!signedIn) return const Stream.empty();
  final repo = ref.watch(ledgerRepositoryProvider);
  unawaited(
    repo.materializeRecurring(DateTime.now()).catchError((Object _) {
      // Non-fatal: the server-side cron job will catch up.
    }),
  );
  return repo.watch();
});

final receiptScannerProvider = Provider<ReceiptScanner>(
  (ref) => MlKitReceiptScanner(),
);

final entitlementRepositoryProvider = Provider<EntitlementRepository>(
  (ref) => MockEntitlementRepository(),
);

class EntitlementNotifier extends AsyncNotifier<Entitlement> {
  EntitlementRepository get _repo => ref.read(entitlementRepositoryProvider);

  @override
  Future<Entitlement> build() => _repo.current();

  Future<void> purchase(SubscriptionPlan plan) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _repo.purchase(plan));
  }

  Future<void> restore() async {
    state = await AsyncValue.guard(_repo.restore);
  }

  Future<void> consumeFreeScan() async {
    state = await AsyncValue.guard(_repo.consumeFreeScan);
  }
}

final entitlementProvider =
    AsyncNotifierProvider<EntitlementNotifier, Entitlement>(
      EntitlementNotifier.new,
    );
