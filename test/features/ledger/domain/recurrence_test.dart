import 'package:flutter_test/flutter_test.dart';
import 'package:split_app/features/ledger/domain/models.dart';
import 'package:split_app/features/ledger/domain/recurrence.dart';

void main() {
  group('next', () {
    test('weekly and fortnightly add days', () {
      expect(
        Recurrence.next(DateTime(2026, 12, 28), RepeatInterval.weekly),
        DateTime(2027, 1, 4),
      );
      expect(
        Recurrence.next(DateTime(2026), RepeatInterval.fortnightly),
        DateTime(2026, 1, 15),
      );
    });

    test('monthly clamps to month end but keeps the anchor day', () {
      final jan31 = DateTime(2026, 1, 31);
      final feb = Recurrence.next(jan31, RepeatInterval.monthly);
      expect(feb, DateTime(2026, 2, 28));
      expect(
        Recurrence.next(feb, RepeatInterval.monthly, anchorDay: 31),
        DateTime(2026, 3, 31),
      );
    });

    test('yearly handles Feb 29', () {
      expect(
        Recurrence.next(DateTime(2028, 2, 29), RepeatInterval.yearly),
        DateTime(2029, 2, 28),
      );
    });
  });

  test('dueBetween returns only dates after the last generated one', () {
    final dates = Recurrence.dueBetween(
      start: DateTime(2026, 1, 31),
      interval: RepeatInterval.monthly,
      after: DateTime(2026, 2, 28),
      until: DateTime(2026, 5),
    );
    expect(dates, [DateTime(2026, 3, 31), DateTime(2026, 4, 30)]);
  });

  test('materialize creates idempotent occurrences', () {
    final template = Expense(
      id: 'rent',
      description: 'Rent',
      totalMinor: 1000,
      currency: 'USD',
      paid: const {'a': 1000},
      owed: const {'a': 500, 'b': 500},
      date: DateTime(2026),
      createdBy: 'a',
      repeat: RepeatInterval.monthly,
    );
    final first = Recurrence.materialize(template, now: DateTime(2026, 3, 15));
    expect(first.map((e) => e.id), ['rent@2026-02-01', 'rent@2026-03-01']);
    expect(first.every((e) => !e.isRecurring), isTrue);
    expect(first.first.owed, template.owed);

    final again = Recurrence.materialize(
      template,
      now: DateTime(2026, 3, 15),
      lastGenerated: DateTime(2026, 3),
    );
    expect(again, isEmpty);
  });
}
