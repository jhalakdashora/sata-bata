import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:split_app/app/app.dart';
import 'package:split_app/app/brand.dart';
import 'package:split_app/app/providers.dart';
import 'package:split_app/features/auth/data/auth_repository.dart';
import 'package:split_app/features/ledger/data/in_memory_ledger_repository.dart';
import 'package:split_app/features/ledger/domain/models.dart';
import 'package:split_app/features/premium/data/entitlement_repository.dart';
import 'package:split_app/features/receipts/data/receipt_scanner.dart';
import 'package:split_app/features/receipts/domain/receipt_parser.dart';

class _FakeScanner implements ReceiptScanner {
  int scans = 0;

  @override
  Future<ScannedReceipt?> scan(ReceiptSource source) async {
    scans++;
    return const ScannedReceipt(
      imagePath: '/tmp/receipt.jpg',
      draft: ReceiptDraft(
        merchant: 'Blue Door Cafe',
        totalMinor: 3000,
        items: [
          ReceiptItem(name: 'Pizza', amountMinor: 2000),
          ReceiptItem(name: 'Salad', amountMinor: 1000),
        ],
      ),
    );
  }
}

class _FakeAuth implements AuthRepository {
  final _changes = StreamController<bool>.broadcast();
  bool _signedIn = false;

  @override
  bool get isSignedIn => _signedIn;

  @override
  Stream<bool> get signedInChanges => _changes.stream;

  @override
  Future<void> signInWithGoogle() async {
    _signedIn = true;
    _changes.add(true);
  }

  @override
  Future<void> signOut() async {
    _signedIn = false;
    _changes.add(false);
  }
}

Future<InMemoryLedgerRepository> _pump(
  WidgetTester tester, {
  ReceiptScanner? scanner,
  AuthRepository? auth,
}) async {
  final repo = InMemoryLedgerRepository();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ledgerRepositoryProvider.overrideWithValue(repo),
        entitlementRepositoryProvider.overrideWithValue(
          MockEntitlementRepository(),
        ),
        if (scanner != null) receiptScannerProvider.overrideWithValue(scanner),
        if (auth != null) authRepositoryProvider.overrideWithValue(auth),
      ],
      child: const SplitApp(),
    ),
  );
  await tester.pumpAndSettle();
  return repo;
}

void main() {
  testWidgets('signed-out users see sign-in, then reach home', (tester) async {
    final auth = _FakeAuth();
    await _pump(tester, auth: auth);
    expect(find.text('Continue with Google'), findsOneWidget);

    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();
    expect(find.text('Flat 4B'), findsOneWidget);

    await tester.tap(find.text('Account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    expect(find.text('Continue with Google'), findsOneWidget);
  });

  testWidgets('comment on an expense', (tester) async {
    final repo = await _pump(tester);
    await tester.tap(find.text('Activity'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Groceries'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Includes the oat milk'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Thanks!');
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Thanks!'), findsOneWidget);
    final snapshot = await repo.watch().first;
    expect(snapshot.commentsFor('e2'), hasLength(2));
  });

  testWidgets('recurring expense saved with repeat interval', (tester) async {
    final repo = await _pump(tester);
    await tester.tap(find.text('Flat 4B'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add expense'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Description'),
      'Internet',
    );
    await tester.enterText(find.widgetWithText(TextField, 'Amount'), '60');
    await tester.tap(find.text('Never'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Monthly').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final snapshot = await repo.watch().first;
    final internet = snapshot.expenses.firstWhere(
      (e) => e.description == 'Internet',
    );
    expect(internet.repeat, RepeatInterval.monthly);
  });

  test('in-memory repo materializes due occurrences once', () async {
    final repo = InMemoryLedgerRepository();
    final later = DateTime.now().add(const Duration(days: 70));
    await repo.materializeRecurring(later);
    await repo.materializeRecurring(later);
    final snapshot = await repo.watch().first;
    final rentCopies = snapshot.expenses.where((e) => e.id.startsWith('e1@'));
    expect(rentCopies.length, greaterThanOrEqualTo(2));
    expect(rentCopies.map((e) => e.id).toSet().length, rentCopies.length);
  });

  testWidgets('free scan prefills the form and uses one free scan', (
    tester,
  ) async {
    final scanner = _FakeScanner();
    await _pump(tester, scanner: scanner);
    await tester.tap(find.text('Add expense'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Scan receipt'));
    await tester.pumpAndSettle();
    expect(find.text('3 free scans left'), findsOneWidget);
    await tester.tap(find.text('Choose from gallery'));
    await tester.pumpAndSettle();

    expect(scanner.scans, 1);
    expect(find.text('Blue Door Cafe'), findsOneWidget);
    expect(find.text('30.00'), findsOneWidget);
    expect(find.text('2 items found'), findsOneWidget);

    // Itemize is Pro: free users get the paywall.
    await tester.tap(find.text('Itemize'));
    await tester.pumpAndSettle();
    expect(find.text(Brand.proName), findsOneWidget);
  });

  testWidgets('group shows its invite code in the add-people sheet', (
    tester,
  ) async {
    await _pump(tester);
    await tester.tap(find.text('Flat 4B'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add people'));
    await tester.pumpAndSettle();
    expect(find.text('FLAT4B23'), findsOneWidget);
    expect(find.text('Share invite'), findsOneWidget);
  });

  testWidgets('join a group by code opens it', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('Join a group'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), ' goa-7trip ');
    await tester.tap(find.text('Join'));
    await tester.pumpAndSettle();
    expect(find.text('Goa trip'), findsWidgets);
    expect(find.byTooltip('Add people'), findsOneWidget);
  });

  testWidgets('wrong invite code shows a message', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('Join a group'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'NOPE1234');
    await tester.tap(find.text('Join'));
    await tester.pumpAndSettle();
    expect(find.textContaining('No group with that code'), findsOneWidget);
  });

  testWidgets('delete a group removes it and returns home', (tester) async {
    final repo = await _pump(tester);
    await tester.tap(find.text('Goa trip'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.more_vert_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete group'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Goa trip'), findsNothing);
    expect(find.text('Flat 4B'), findsOneWidget);
    final snapshot = await repo.watch().first;
    expect(snapshot.expenses.where((e) => e.groupId == 'g-goa'), isEmpty);
  });

  testWidgets('creating a group with an existing name offers to open it', (
    tester,
  ) async {
    await _pump(tester);
    await tester.tap(find.text('New group'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'flat 4b');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    expect(find.textContaining('You already have'), findsOneWidget);
    await tester.tap(find.text('Open it'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Add people'), findsOneWidget);
  });

  testWidgets('simplify debts can be switched off and on', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('Flat 4B'));
    await tester.pumpAndSettle();
    Switch toggle() => tester.widget<Switch>(
      find.descendant(
        of: find.widgetWithText(SwitchListTile, 'Simplify debts'),
        matching: find.byType(Switch),
      ),
    );
    expect(toggle().value, isTrue);
    await tester.tap(find.text('Simplify debts'));
    await tester.pumpAndSettle();
    expect(toggle().value, isFalse);
    await tester.tap(find.text('Simplify debts'));
    await tester.pumpAndSettle();
    expect(toggle().value, isTrue);
  });

  testWidgets('pull to refresh refetches on home and group screens', (
    tester,
  ) async {
    final repo = _CountingRepo();
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
    await tester.fling(find.text('Flat 4B'), const Offset(0, 400), 1000);
    await tester.pumpAndSettle();
    expect(repo.refreshes, 1);

    await tester.tap(find.text('Flat 4B'));
    await tester.pumpAndSettle();
    await tester.fling(find.text('Simplify debts'), const Offset(0, 400), 1000);
    await tester.pumpAndSettle();
    expect(repo.refreshes, 2);
  });
}

class _CountingRepo extends InMemoryLedgerRepository {
  int refreshes = 0;

  @override
  Future<void> refresh() {
    refreshes++;
    return super.refresh();
  }
}
