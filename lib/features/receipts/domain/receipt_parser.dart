import 'package:meta/meta.dart';

@immutable
class ReceiptItem {
  const new({required this.name, required this.amountMinor});
  final String name;
  final int amountMinor;

  @override
  bool operator ==(Object other) =>
      other is ReceiptItem &&
      other.name == name &&
      other.amountMinor == amountMinor;

  @override
  int get hashCode => Object.hash(name, amountMinor);

  @override
  String toString() => 'ReceiptItem($name, $amountMinor)';
}

/// Best-effort structure extracted from OCR text. Every field is optional:
/// the user always reviews it before saving.
@immutable
class ReceiptDraft {
  const new({
    this.merchant,
    this.totalMinor,
    this.date,
    this.items = const [],
    this.taxMinor = 0,
    this.tipMinor = 0,
  });

  final String? merchant;
  final int? totalMinor;
  final DateTime? date;
  final List<ReceiptItem> items;
  final int taxMinor;
  final int tipMinor;

  int get itemsSubtotal => items.fold(0, (s, i) => s + i.amountMinor);
}

/// Turns OCR lines (top to bottom) into a [ReceiptDraft]. Pure Dart, so it is
/// unit-testable without a camera or ML Kit.
abstract final class ReceiptParser {
  static final _amount = RegExp(r'(-?\d{1,6}(?:[.,]\d{3})*[.,]\d{2})\s*$');
  static final _totalLabel = RegExp(
    r'\b(grand\s*total|total\s*due|amount\s*due|balance\s*due|total)\b',
    caseSensitive: false,
  );
  static final _subtotalLabel = RegExp(
    r'\b(sub\s*-?\s*total)\b',
    caseSensitive: false,
  );
  static final _taxLabel = RegExp(r'\b(tax|vat|gst)\b', caseSensitive: false);
  static final _tipLabel = RegExp(
    r'\b(tip|gratuity|service charge)\b',
    caseSensitive: false,
  );
  static final _skipLabel = RegExp(
    r'\b(change|cash|card|visa|mastercard|amex|tender|paid|payment|balance)\b',
    caseSensitive: false,
  );
  static final _isoDate = RegExp(r'\b(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})\b');
  static final _dmyDate = RegExp(r'\b(\d{1,2})[-/.](\d{1,2})[-/.](\d{2,4})\b');

  static ReceiptDraft parse(List<String> lines) {
    final clean = [
      for (final l in lines)
        if (l.trim().isNotEmpty) l.trim(),
    ];
    int? total;
    var tax = 0;
    var tip = 0;
    DateTime? date;
    final items = <ReceiptItem>[];

    for (final line in clean) {
      date ??= _parseDate(line);
      final amountMatch = _amount.firstMatch(line);
      if (amountMatch == null) continue;
      final amount = _toMinor(amountMatch.group(1)!);
      final label = line.substring(0, amountMatch.start).trim();

      if (_subtotalLabel.hasMatch(label)) continue;
      if (_totalLabel.hasMatch(label)) {
        // Prefer the largest "total" line (grand total after tax/tip).
        if (total == null || amount > total) total = amount;
        continue;
      }
      if (_taxLabel.hasMatch(label)) {
        tax += amount;
        continue;
      }
      if (_tipLabel.hasMatch(label)) {
        tip += amount;
        continue;
      }
      if (_skipLabel.hasMatch(label)) continue;
      final name = _cleanItemName(label);
      if (name.isEmpty || amount <= 0) continue;
      items.add(ReceiptItem(name: name, amountMinor: amount));
    }

    total ??= items.isEmpty
        ? null
        : items.fold<int>(0, (s, i) => s + i.amountMinor) + tax + tip;

    return ReceiptDraft(
      merchant: _merchant(clean),
      totalMinor: total,
      date: date,
      items: items,
      taxMinor: tax,
      tipMinor: tip,
    );
  }

  /// Merchant is usually the first line that is mostly letters.
  static String? _merchant(List<String> lines) {
    for (final l in lines.take(5)) {
      final letters = l.replaceAll(RegExp('[^A-Za-z]'), '').length;
      if (letters >= 3 && letters >= l.length * 0.5 && !_amount.hasMatch(l)) {
        return l;
      }
    }
    return null;
  }

  static String _cleanItemName(String label) => label
      .replaceFirst(RegExp(r'^\d+\s*[xX@]?\s+'), '') // leading quantity "2 x"
      .replaceAll(RegExp(r'[\s.$€£₹]+$'), '')
      .trim();

  static int _toMinor(String raw) {
    // Normalise "1.234,56" and "1,234.56" to "1234.56".
    var s = raw;
    final lastSep = s.lastIndexOf(RegExp('[.,]'));
    s =
        '${s.substring(0, lastSep).replaceAll(RegExp('[.,]'), '')}.'
        '${s.substring(lastSep + 1)}';
    return (double.parse(s) * 100).round();
  }

  static DateTime? _parseDate(String line) {
    final iso = _isoDate.firstMatch(line);
    if (iso != null) {
      return _safeDate(
        int.parse(iso.group(1)!),
        int.parse(iso.group(2)!),
        int.parse(iso.group(3)!),
      );
    }
    final dmy = _dmyDate.firstMatch(line);
    if (dmy != null) {
      var year = int.parse(dmy.group(3)!);
      if (year < 100) year += 2000;
      final a = int.parse(dmy.group(1)!);
      final b = int.parse(dmy.group(2)!);
      // Ambiguous: assume day/month unless the first part can't be a day.
      return a > 12 || b <= 12
          ? _safeDate(year, b, a) ?? _safeDate(year, a, b)
          : _safeDate(year, a, b);
    }
    return null;
  }

  static DateTime? _safeDate(int y, int m, int d) {
    if (m < 1 || m > 12 || d < 1 || d > 31) return null;
    final date = DateTime(y, m, d);
    return date.month == m ? date : null;
  }
}
