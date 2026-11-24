import 'package:collection/collection.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:split_app/features/ledger/domain/models.dart';
import 'package:split_app/features/ledger/domain/split_calculator.dart';

void main() {
  const abc = ['a', 'b', 'c'];

  Map<String, int> split(
    int total,
    SplitMethod method, [
    Map<String, int> inputs = const {},
  ]) => SplitCalculator.compute(
    totalMinor: total,
    participantIds: abc,
    method: method,
    inputs: inputs,
  );

  group('equal', () {
    test('divides evenly', () {
      expect(split(900, SplitMethod.equal), {'a': 300, 'b': 300, 'c': 300});
    });

    test('distributes leftover cents deterministically and sums to total', () {
      final r = split(1000, SplitMethod.equal);
      expect(r, {'a': 334, 'b': 333, 'c': 333});
      expect(r.values.sum, 1000);
    });
  });

  group('exact', () {
    test('accepts amounts that match the total', () {
      expect(split(1000, SplitMethod.exact, {'a': 500, 'b': 300, 'c': 200}), {
        'a': 500,
        'b': 300,
        'c': 200,
      });
    });

    test('rejects amounts that do not match', () {
      expect(
        () => split(1000, SplitMethod.exact, {'a': 500, 'b': 300}),
        throwsA(isA<SplitException>()),
      );
    });
  });

  group('percent', () {
    test('uses basis points and sums to total', () {
      final r = split(1001, SplitMethod.percent, {
        'a': 5000,
        'b': 2500,
        'c': 2500,
      });
      expect(r.values.sum, 1001);
      expect(r['a'], 501);
    });

    test('rejects percentages not totalling 100', () {
      expect(
        () =>
            split(1000, SplitMethod.percent, {'a': 5000, 'b': 2000, 'c': 2000}),
        throwsA(isA<SplitException>()),
      );
    });
  });

  group('shares', () {
    test('splits by weight', () {
      expect(split(1200, SplitMethod.shares, {'a': 2, 'b': 1, 'c': 1}), {
        'a': 600,
        'b': 300,
        'c': 300,
      });
    });

    test('zero shares owe nothing', () {
      final r = split(1001, SplitMethod.shares, {'a': 1, 'b': 1, 'c': 0});
      expect(r['c'], 0);
      expect(r.values.sum, 1001);
    });

    test('requires at least one share', () {
      expect(
        () => split(1000, SplitMethod.shares),
        throwsA(isA<SplitException>()),
      );
    });
  });

  group('adjustment', () {
    test('adds adjustments on top of equal split of remainder', () {
      // 1000 - 100 adjustment = 900 split equally, a pays +100.
      expect(split(1000, SplitMethod.adjustment, {'a': 100}), {
        'a': 400,
        'b': 300,
        'c': 300,
      });
    });

    test('rejects adjustments above total', () {
      expect(
        () => split(100, SplitMethod.adjustment, {'a': 200}),
        throwsA(isA<SplitException>()),
      );
    });
  });

  test('rejects empty participants', () {
    expect(
      () => SplitCalculator.compute(
        totalMinor: 100,
        participantIds: const [],
        method: SplitMethod.equal,
      ),
      throwsA(isA<SplitException>()),
    );
  });
}
