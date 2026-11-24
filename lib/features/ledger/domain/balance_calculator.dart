import 'package:split_app/features/ledger/domain/models.dart';

/// Pure functions that derive balances and debts from expenses.
abstract final class BalanceCalculator {
  /// Net position per member per currency: positive = is owed money,
  /// negative = owes money. Returns currency -> memberId -> minor units.
  static Map<String, Map<String, int>> netBalances(Iterable<Expense> expenses) {
    final result = <String, Map<String, int>>{};
    for (final e in expenses) {
      final bucket = result.putIfAbsent(e.currency, () => {});
      e.paid.forEach((id, v) => bucket[id] = (bucket[id] ?? 0) + v);
      e.owed.forEach((id, v) => bucket[id] = (bucket[id] ?? 0) - v);
    }
    for (final bucket in result.values) {
      bucket.removeWhere((_, v) => v == 0);
    }
    result.removeWhere((_, bucket) => bucket.isEmpty);
    return result;
  }

  /// Pairwise debts without simplification: each expense creates debts from
  /// the people who under-paid to the people who over-paid, then debts between
  /// the same two people are netted across expenses.
  static List<Debt> pairwiseDebts(Iterable<Expense> expenses) {
    // currency -> (from, to) -> amount, with from < to canonical ordering.
    final ledger = <String, Map<(String, String), int>>{};
    for (final e in expenses) {
      final net = <String, int>{};
      e.paid.forEach((id, v) => net[id] = (net[id] ?? 0) + v);
      e.owed.forEach((id, v) => net[id] = (net[id] ?? 0) - v);
      for (final debt in _settle(net, e.currency)) {
        final bucket = ledger.putIfAbsent(e.currency, () => {});
        final forward = debt.from.compareTo(debt.to) < 0;
        final key = forward ? (debt.from, debt.to) : (debt.to, debt.from);
        final signed = forward ? debt.amountMinor : -debt.amountMinor;
        bucket[key] = (bucket[key] ?? 0) + signed;
      }
    }
    final debts = <Debt>[];
    ledger.forEach((currency, bucket) {
      bucket.forEach((key, amount) {
        if (amount > 0) {
          debts.add(
            Debt(
              from: key.$1,
              to: key.$2,
              amountMinor: amount,
              currency: currency,
            ),
          );
        } else if (amount < 0) {
          debts.add(
            Debt(
              from: key.$2,
              to: key.$1,
              amountMinor: -amount,
              currency: currency,
            ),
          );
        }
      });
    });
    return debts;
  }

  /// "Simplify debts": minimise the number of payments by settling net
  /// balances directly (greedy largest-creditor / largest-debtor matching).
  /// Everyone's net position is unchanged.
  static List<Debt> simplifiedDebts(Iterable<Expense> expenses) => [
    for (final entry in netBalances(expenses).entries)
      ..._settle(entry.value, entry.key),
  ];

  /// Debts for [expenses] honouring the group's simplify setting.
  static List<Debt> debtsFor(
    Iterable<Expense> expenses, {
    required bool simplify,
  }) => simplify ? simplifiedDebts(expenses) : pairwiseDebts(expenses);

  /// Greedy settlement of a net-balance map (must sum to zero).
  static List<Debt> _settle(Map<String, int> net, String currency) {
    final creditors = <MapEntry<String, int>>[
      for (final e in net.entries)
        if (e.value > 0) e,
    ];
    final debtors = <MapEntry<String, int>>[
      for (final e in net.entries)
        if (e.value < 0) MapEntry(e.key, -e.value),
    ];
    int byAmountThenId(MapEntry<String, int> a, MapEntry<String, int> b) {
      final c = b.value.compareTo(a.value);
      return c != 0 ? c : a.key.compareTo(b.key);
    }

    creditors.sort(byAmountThenId);
    debtors.sort(byAmountThenId);

    final debts = <Debt>[];
    var ci = 0;
    var di = 0;
    var credit = creditors.isEmpty ? 0 : creditors[0].value;
    var debit = debtors.isEmpty ? 0 : debtors[0].value;
    while (ci < creditors.length && di < debtors.length) {
      final amount = credit < debit ? credit : debit;
      if (amount > 0) {
        debts.add(
          Debt(
            from: debtors[di].key,
            to: creditors[ci].key,
            amountMinor: amount,
            currency: currency,
          ),
        );
      }
      credit -= amount;
      debit -= amount;
      if (credit == 0 && ++ci < creditors.length) credit = creditors[ci].value;
      if (debit == 0 && ++di < debtors.length) debit = debtors[di].value;
    }
    return debts;
  }
}
