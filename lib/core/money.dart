import 'package:intl/intl.dart';
import 'package:meta/meta.dart';

/// The app's single currency. Change these three values to switch currency
/// (existing data keeps the currency it was saved with).
abstract final class AppCurrency {
  static const code = 'INR';
  static const symbol = '₹';
  static const locale = 'en_IN';
}

/// Money is stored as integer minor units (e.g. cents) to avoid floating
/// point rounding errors in ledger math.
@immutable
class Money implements Comparable<Money> {
  const new(this.minor, this.currency);

  const new zero(this.currency) : minor = 0;

  /// Parses user input such as "12.5" into minor units for [currency].
  /// Returns null when the input is not a valid non-negative amount.
  static Money? tryParse(String input, String currency) {
    final cleaned = input.trim().replaceAll(',', '');
    final match = RegExp(r'^(\d+)(?:\.(\d{0,2}))?$').firstMatch(cleaned);
    if (match == null) return null;
    final whole = int.parse(match.group(1)!);
    final frac = (match.group(2) ?? '').padRight(2, '0');
    return Money(whole * 100 + int.parse(frac), currency);
  }

  final int minor;
  final String currency;

  bool get isZero => minor == 0;
  bool get isPositive => minor > 0;
  bool get isNegative => minor < 0;

  Money operator +(Money other) {
    _assertSameCurrency(other);
    return Money(minor + other.minor, currency);
  }

  Money operator -(Money other) {
    _assertSameCurrency(other);
    return Money(minor - other.minor, currency);
  }

  Money operator -() => Money(-minor, currency);

  Money abs() => Money(minor.abs(), currency);

  /// Formats for display, e.g. ₹1,23,456.50 for INR (Indian grouping).
  String format() =>
      (currency == AppCurrency.code
              ? NumberFormat.currency(
                  locale: AppCurrency.locale,
                  symbol: AppCurrency.symbol,
                  decimalDigits: 2,
                )
              : NumberFormat.simpleCurrency(name: currency))
          .format(minor / 100);

  void _assertSameCurrency(Money other) {
    if (other.currency != currency) {
      throw ArgumentError('Currency mismatch: $currency vs ${other.currency}');
    }
  }

  @override
  int compareTo(Money other) {
    _assertSameCurrency(other);
    return minor.compareTo(other.minor);
  }

  @override
  bool operator ==(Object other) =>
      other is Money && other.minor == minor && other.currency == currency;

  @override
  int get hashCode => Object.hash(minor, currency);

  @override
  String toString() => '$currency ${(minor / 100).toStringAsFixed(2)}';
}
