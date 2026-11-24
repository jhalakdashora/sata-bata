import 'package:collection/collection.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:split_app/features/ledger/domain/balance_calculator.dart';
import 'package:split_app/features/ledger/domain/models.dart';

Expense _expense(
  String id,
  Map<String, int> paid,
  Map<String, int> owed, {
  String currency = 'USD',
}) => Expense(
  id: id,
  description: id,
  totalMinor: paid.values.sum,
  currency: currency,
  paid: paid,
  owed: owed,
  date: DateTime(2026),
  createdBy: paid.keys.first,
);

void main() {
  test('Expense rejects unbalanced paid/owed', () {
    expect(
      () => _expense('x', {'a': 100}, {'a': 50, 'b': 40}),
      throwsArgumentError,
    );
  });

  test('net balances sum to zero per currency', () {
    final expenses = [
      _expense('1', {'a': 900}, {'a': 300, 'b': 300, 'c': 300}),
      _expense('2', {'b': 600}, {'a': 200, 'b': 200, 'c': 200}),
    ];
    final net = BalanceCalculator.netBalances(expenses)['USD']!;
    expect(net, {'a': 400, 'b': 100, 'c': -500});
    expect(net.values.sum, 0);
  });

  test('currencies are kept separate', () {
    final net = BalanceCalculator.netBalances([
      _expense('1', {'a': 100}, {'b': 100}),
      _expense('2', {'b': 100}, {'a': 100}, currency: 'EUR'),
    ]);
    expect(net['USD'], {'a': 100, 'b': -100});
    expect(net['EUR'], {'a': -100, 'b': 100});
  });

  test('simplify debts: A->B->C chain becomes A->C', () {
    // Classic example: B lends A 10, C lends B 10.
    final expenses = [
      _expense('1', {'b': 1000}, {'a': 1000}),
      _expense('2', {'c': 1000}, {'b': 1000}),
    ];
    expect(BalanceCalculator.pairwiseDebts(expenses).length, 2);
    expect(BalanceCalculator.simplifiedDebts(expenses), [
      const Debt(from: 'a', to: 'c', amountMinor: 1000, currency: 'USD'),
    ]);
  });

  test('pairwise debts net out between the same two people', () {
    final debts = BalanceCalculator.pairwiseDebts([
      _expense('1', {'a': 1000}, {'b': 1000}),
      _expense('2', {'b': 400}, {'a': 400}),
    ]);
    expect(debts, [
      const Debt(from: 'b', to: 'a', amountMinor: 600, currency: 'USD'),
    ]);
  });

  test('a payment settles the balance', () {
    final expenses = [
      _expense('1', {'a': 1000}, {'a': 500, 'b': 500}),
      Expense(
        id: 'p',
        description: 'Payment',
        totalMinor: 500,
        currency: 'USD',
        paid: const {'b': 500},
        owed: const {'a': 500},
        date: DateTime(2026),
        createdBy: 'b',
        kind: ExpenseKind.payment,
      ),
    ];
    expect(BalanceCalculator.netBalances(expenses), isEmpty);
    expect(BalanceCalculator.simplifiedDebts(expenses), isEmpty);
  });

  test("simplified debts preserve everyone's net balance", () {
    final expenses = [
      _expense('1', {'a': 3000}, {'a': 750, 'b': 750, 'c': 750, 'd': 750}),
      _expense('2', {'b': 1200}, {'a': 400, 'c': 400, 'd': 400}),
      _expense('3', {'c': 999}, {'a': 333, 'b': 333, 'd': 333}),
    ];
    final net = BalanceCalculator.netBalances(expenses)['USD']!;
    final fromDebts = <String, int>{};
    for (final d in BalanceCalculator.simplifiedDebts(expenses)) {
      fromDebts[d.from] = (fromDebts[d.from] ?? 0) - d.amountMinor;
      fromDebts[d.to] = (fromDebts[d.to] ?? 0) + d.amountMinor;
    }
    expect(fromDebts, net);
  });
}
