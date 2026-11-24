import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:split_app/app/app.dart';
import 'package:split_app/app/brand.dart';
import 'package:split_app/app/providers.dart';
import 'package:split_app/features/ledger/data/in_memory_ledger_repository.dart';
import 'package:split_app/features/premium/data/entitlement_repository.dart';

Future<InMemoryLedgerRepository> _pumpApp(WidgetTester tester) async {
  final repo = InMemoryLedgerRepository();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ledgerRepositoryProvider.overrideWithValue(repo),
        entitlementRepositoryProvider.overrideWithValue(
          MockEntitlementRepository(),
        ),
      ],
      child: const SplitApp(),
    ),
  );
  await tester.pumpAndSettle();
  return repo;
}

void main() {
  testWidgets('dashboard shows groups and overall balance', (tester) async {
    await _pumpApp(tester);
    expect(find.text('Flat 4B'), findsOneWidget);
    expect(find.text('Goa trip'), findsOneWidget);
    expect(find.text('Overall'), findsOneWidget);
  });

  testWidgets('adding an equal-split expense to a group', (tester) async {
    final repo = await _pumpApp(tester);
    await tester.tap(find.text('Flat 4B'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add expense'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Description'),
      'Pizza',
    );
    await tester.enterText(find.widgetWithText(TextField, 'Amount'), '30');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final snapshot = await repo.watch().first;
    final pizza = snapshot.expenses.firstWhere((e) => e.description == 'Pizza');
    expect(pizza.totalMinor, 3000);
    expect(pizza.owed, {'me': 1000, 'alex': 1000, 'sam': 1000});
    expect(find.text('Pizza'), findsOneWidget);
  });

  testWidgets('validation error for missing amount', (tester) async {
    await _pumpApp(tester);
    await tester.tap(find.text('Add expense'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Description'),
      'Coffee',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a valid amount'), findsOneWidget);
  });

  testWidgets('search is Pro-gated and unlocks after demo purchase', (
    tester,
  ) async {
    await _pumpApp(tester);
    await tester.tap(find.byTooltip('Search'));
    await tester.pumpAndSettle();
    expect(find.text(Brand.proName), findsOneWidget);

    await tester.tap(find.text('Start Pro (demo purchase)'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    // Back on home, search opened after upgrading.
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('settle up records a payment and clears the debt', (
    tester,
  ) async {
    final repo = await _pumpApp(tester);
    await tester.tap(find.text('Flat 4B'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settle up'));
    await tester.pumpAndSettle();

    final records = find.text('Record');
    final count = records.evaluate().length;
    expect(count, greaterThan(0));
    await tester.tap(records.first);
    await tester.pumpAndSettle();

    final snapshot = await repo.watch().first;
    expect(snapshot.expenses.where((e) => e.isPayment), hasLength(1));
  });
}
