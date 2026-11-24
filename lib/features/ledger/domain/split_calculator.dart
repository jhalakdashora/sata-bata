import 'package:collection/collection.dart';

import 'package:split_app/features/ledger/domain/models.dart';

class SplitException implements Exception {
  const new(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Turns a total plus per-person inputs into exact owed amounts (minor units)
/// that always sum to the total. Leftover cents from rounding are handed out
/// one at a time, by largest fractional remainder, ties broken by input order,
/// so results are deterministic.
abstract final class SplitCalculator {
  /// [inputs] meaning depends on [method]:
  /// - equal: ignored (all [participantIds] share equally)
  /// - exact: minor units per person; must sum to [totalMinor]
  /// - percent: basis points per person (100% = 10000); must sum to 10000
  /// - shares: positive integer weights
  /// - adjustment: extra minor units per person; remainder split equally
  static Map<String, int> compute({
    required int totalMinor,
    required List<String> participantIds,
    required SplitMethod method,
    Map<String, int> inputs = const {},
  }) {
    if (totalMinor < 0) throw const SplitException('Amount cannot be negative');
    if (participantIds.isEmpty) {
      throw const SplitException('Choose at least one person');
    }
    if (participantIds.toSet().length != participantIds.length) {
      throw const SplitException('Duplicate participants');
    }

    switch (method) {
      case SplitMethod.equal:
        return _byWeights(totalMinor, {for (final id in participantIds) id: 1});
      case SplitMethod.exact:
        final values = _inputsFor(participantIds, inputs);
        final sum = values.values.sum;
        if (values.values.any((v) => v < 0)) {
          throw const SplitException('Amounts cannot be negative');
        }
        if (sum != totalMinor) {
          throw SplitException(
            'Amounts add up to $sum, expected $totalMinor '
            '(${sum > totalMinor ? 'over' : 'under'} by '
            '${(sum - totalMinor).abs()})',
          );
        }
        return values;
      case SplitMethod.percent:
        final bps = _inputsFor(participantIds, inputs);
        if (bps.values.any((v) => v < 0)) {
          throw const SplitException('Percentages cannot be negative');
        }
        final sum = bps.values.sum;
        if (sum != 10000) {
          throw SplitException(
            "Percentages don't add up to 100% "
            '(${sum > 10000 ? 'over' : 'under'} by '
            '${((sum - 10000).abs() / 100).toStringAsFixed(2)}%)',
          );
        }
        return _byWeights(totalMinor, bps);
      case SplitMethod.shares:
        final shares = _inputsFor(participantIds, inputs);
        if (shares.values.any((v) => v < 0)) {
          throw const SplitException('Shares cannot be negative');
        }
        if (shares.values.sum == 0) {
          throw const SplitException('Assign at least 1 share');
        }
        return _byWeights(totalMinor, shares);
      case SplitMethod.adjustment:
        final adj = _inputsFor(participantIds, inputs);
        if (adj.values.any((v) => v < 0)) {
          throw const SplitException('Adjustments cannot be negative');
        }
        final adjSum = adj.values.sum;
        if (adjSum > totalMinor) {
          throw SplitException(
            'Adjustments exceed the total by ${adjSum - totalMinor}',
          );
        }
        final base = _byWeights(totalMinor - adjSum, {
          for (final id in participantIds) id: 1,
        });
        return {for (final id in participantIds) id: base[id]! + adj[id]!};
    }
  }

  static Map<String, int> _inputsFor(
    List<String> ids,
    Map<String, int> inputs,
  ) => {for (final id in ids) id: inputs[id] ?? 0};

  /// Largest-remainder apportionment of [total] by integer [weights].
  static Map<String, int> _byWeights(int total, Map<String, int> weights) {
    final weightSum = weights.values.sum;
    final result = <String, int>{};
    final remainders = <(String, int, int)>[]; // (id, remainder, order)
    var allocated = 0;
    var order = 0;
    for (final entry in weights.entries) {
      final exact = total * entry.value;
      final floor = exact ~/ weightSum;
      result[entry.key] = floor;
      allocated += floor;
      remainders.add((entry.key, exact % weightSum, order++));
    }
    var leftover = total - allocated;
    remainders.sort((a, b) {
      final byRemainder = b.$2.compareTo(a.$2);
      return byRemainder != 0 ? byRemainder : a.$3.compareTo(b.$3);
    });
    for (final (id, remainder, _) in remainders) {
      if (leftover == 0) break;
      // Zero-weight participants never receive leftover cents.
      if (weights[id] == 0 && remainder == 0) continue;
      result[id] = result[id]! + 1;
      leftover--;
    }
    return result;
  }
}
