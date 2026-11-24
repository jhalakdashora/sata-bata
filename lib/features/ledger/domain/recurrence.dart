import 'package:split_app/features/ledger/domain/models.dart';

/// Date math for recurring expenses.
abstract final class Recurrence {
  /// The occurrence after [from]. Monthly/yearly repeats keep the original
  /// [anchorDay] and clamp to the month's last day (Jan 31 -> Feb 28 ->
  /// Mar 31).
  static DateTime next(
    DateTime from,
    RepeatInterval interval, {
    int? anchorDay,
  }) {
    final day = anchorDay ?? from.day;
    return switch (interval) {
      RepeatInterval.never => throw ArgumentError('never does not repeat'),
      RepeatInterval.weekly => _addDays(from, 7),
      RepeatInterval.fortnightly => _addDays(from, 14),
      RepeatInterval.monthly => _clamped(from, from.year, from.month + 1, day),
      RepeatInterval.yearly => _clamped(from, from.year + 1, from.month, day),
    };
  }

  /// All occurrence dates of a series starting at [start] that fall in
  /// (`after`, [until]], i.e. strictly after the last generated date.
  static List<DateTime> dueBetween({
    required DateTime start,
    required RepeatInterval interval,
    required DateTime after,
    required DateTime until,
    int max = 366,
  }) {
    if (interval == RepeatInterval.never) return const [];
    final dates = <DateTime>[];
    var current = start;
    while (dates.length < max) {
      current = next(current, interval, anchorDay: start.day);
      if (current.isAfter(until)) break;
      if (current.isAfter(after)) dates.add(current);
    }
    return dates;
  }

  /// Generates the missing occurrences of [template] up to [now]. Occurrence
  /// ids are deterministic (`<templateId>@<yyyy-mm-dd>`) so running this
  /// twice never duplicates expenses.
  static List<Expense> materialize(
    Expense template, {
    required DateTime now,
    DateTime? lastGenerated,
  }) => [
    for (final date in dueBetween(
      start: template.date,
      interval: template.repeat,
      after: lastGenerated ?? template.date,
      until: now,
    ))
      template.copyWith(
        id: occurrenceId(template.id, date),
        date: date,
        repeat: RepeatInterval.never,
      ),
  ];

  static String occurrenceId(String templateId, DateTime date) =>
      '$templateId@${date.toIso8601String().split('T').first}';

  static DateTime _addDays(DateTime d, int days) =>
      DateTime(d.year, d.month, d.day + days, d.hour, d.minute);

  static DateTime _clamped(DateTime from, int year, int month, int day) {
    final lastDay = DateTime(year, month + 1, 0).day;
    return DateTime(
      year,
      month,
      day > lastDay ? lastDay : day,
      from.hour,
      from.minute,
    );
  }
}
