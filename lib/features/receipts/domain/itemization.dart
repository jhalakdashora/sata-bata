import 'package:split_app/features/ledger/domain/split_calculator.dart';
import 'package:split_app/features/receipts/domain/receipt_parser.dart';

/// Converts receipt items assigned to people into exact owed amounts.
/// Each item is split equally among its assignees; tax and tip are shared
/// proportionally to each person's item subtotal.
abstract final class Itemization {
  static Map<String, int> owedAmounts({
    required List<ReceiptItem> items,
    required Map<int, Set<String>> assignments,
    required int taxMinor,
    required int tipMinor,
  }) {
    final subtotals = <String, int>{};
    for (var i = 0; i < items.length; i++) {
      final people = assignments[i] ?? const <String>{};
      if (people.isEmpty) {
        throw SplitException(
          'Assign "${items[i].name}" to at least one person',
        );
      }
      final ids = people.toList()..sort();
      final shares = SplitCalculator.compute(
        totalMinor: items[i].amountMinor,
        participantIds: ids,
        method: .equal,
      );
      for (final MapEntry(key: id, value: v) in shares.entries) {
        subtotals[id] = (subtotals[id] ?? 0) + v;
      }
    }
    final extras = taxMinor + tipMinor;
    if (extras == 0) return subtotals;

    final ids = subtotals.keys.toList()..sort();
    final extraShares = SplitCalculator.compute(
      totalMinor: extras,
      participantIds: ids,
      method: .shares,
      inputs: subtotals,
    );
    return {for (final id in ids) id: subtotals[id]! + extraShares[id]!};
  }
}
