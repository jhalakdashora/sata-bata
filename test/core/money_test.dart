import 'package:flutter_test/flutter_test.dart';
import 'package:split_app/core/money.dart';

void main() {
  test('app currency is rupees with Indian digit grouping', () {
    expect(AppCurrency.code, 'INR');
    expect(const Money(12345650, 'INR').format(), '₹1,23,456.50');
    expect(const Money(99, 'INR').format(), '₹0.99');
    expect(const Money(0, 'INR').format(), isNot(contains(r'$')));
  });

  test('parses typed amounts into paise', () {
    expect(Money.tryParse('1,200.5', 'INR'), const Money(120050, 'INR'));
    expect(Money.tryParse('abc', 'INR'), isNull);
  });
}
