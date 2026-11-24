import 'package:flutter_test/flutter_test.dart';
import 'package:split_app/features/ledger/domain/split_calculator.dart';
import 'package:split_app/features/receipts/domain/itemization.dart';
import 'package:split_app/features/receipts/domain/receipt_parser.dart';

void main() {
  group('ReceiptParser', () {
    test('parses a typical restaurant receipt', () {
      final draft = ReceiptParser.parse([
        'BLUE DOOR CAFE',
        '123 Main St',
        'Date: 2026-11-20 19:42',
        '2 x Margherita Pizza   24.00',
        'Caesar Salad 9.50',
        'Lemonade 3.50',
        'Subtotal 37.00',
        'Tax 3.33',
        'Tip 5.00',
        'TOTAL 45.33',
        'VISA 45.33',
      ]);
      expect(draft.merchant, 'BLUE DOOR CAFE');
      expect(draft.date, DateTime(2026, 11, 20));
      expect(draft.totalMinor, 4533);
      expect(draft.taxMinor, 333);
      expect(draft.tipMinor, 500);
      expect(draft.items, const [
        ReceiptItem(name: 'Margherita Pizza', amountMinor: 2400),
        ReceiptItem(name: 'Caesar Salad', amountMinor: 950),
        ReceiptItem(name: 'Lemonade', amountMinor: 350),
      ]);
    });

    test('handles European decimal commas and d/m/y dates', () {
      final draft = ReceiptParser.parse([
        'Bäckerei Schmidt',
        '21.11.2026',
        'Brot 3,20',
        'Summe Total 1.003,20',
      ]);
      expect(draft.date, DateTime(2026, 11, 21));
      expect(draft.totalMinor, 100320);
    });

    test('falls back to sum of items when no total line', () {
      final draft = ReceiptParser.parse(['Shop', 'Apples 2.00', 'Pears 3.00']);
      expect(draft.totalMinor, 500);
    });

    test('empty OCR yields empty draft', () {
      final draft = ReceiptParser.parse(const []);
      expect(draft.totalMinor, isNull);
      expect(draft.items, isEmpty);
    });
  });

  group('Itemization', () {
    const items = [
      ReceiptItem(name: 'Pizza', amountMinor: 2400),
      ReceiptItem(name: 'Salad', amountMinor: 950),
      ReceiptItem(name: 'Lemonade', amountMinor: 350),
    ];

    test('splits shared items and spreads tax/tip proportionally', () {
      final owed = Itemization.owedAmounts(
        items: items,
        assignments: {
          0: {'a', 'b'},
          1: {'b'},
          2: {'a'},
        },
        taxMinor: 333,
        tipMinor: 500,
      );
      // a: 1200 + 350 = 1550; b: 1200 + 950 = 2150; extras 833.
      expect(owed.values.fold<int>(0, (s, v) => s + v), 3700 + 833);
      expect(owed['a'], 1550 + 349);
      expect(owed['b'], 2150 + 484);
    });

    test('rejects unassigned items', () {
      expect(
        () => Itemization.owedAmounts(
          items: items,
          assignments: {
            0: {'a'},
          },
          taxMinor: 0,
          tipMinor: 0,
        ),
        throwsA(isA<SplitException>()),
      );
    });
  });
}
