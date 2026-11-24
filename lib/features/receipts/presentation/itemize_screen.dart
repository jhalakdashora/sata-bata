import 'package:material_ui/material_ui.dart';
import 'package:split_app/features/ledger/domain/split_calculator.dart';
import 'package:split_app/features/ledger/presentation/widgets.dart';
import 'package:split_app/features/receipts/domain/itemization.dart';
import 'package:split_app/features/receipts/domain/receipt_parser.dart';

/// Pro: assign each receipt item to people. Pops with memberId -> owed
/// minor units (summing to items + tax + tip).
class ItemizeScreen extends StatefulWidget {
  const new({
    super.key,
    required this.draft,
    required this.people,
    required this.currency,
  });

  final ReceiptDraft draft;

  /// memberId -> display name.
  final Map<String, String> people;
  final String currency;

  @override
  State<ItemizeScreen> createState() => _ItemizeScreenState();
}

class _ItemizeScreenState extends State<ItemizeScreen> {
  late final Map<int, Set<String>> _assignments = {
    for (var i = 0; i < widget.draft.items.length; i++)
      i: widget.people.keys.toSet(),
  };
  String? _error;

  Map<String, int>? _tryCompute() {
    try {
      return Itemization.owedAmounts(
        items: widget.draft.items,
        assignments: _assignments,
        taxMinor: widget.draft.taxMinor,
        tipMinor: widget.draft.tipMinor,
      );
    } on SplitException {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final totals = _tryCompute();
    final items = widget.draft.items;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Itemize receipt'),
        actions: [
          TextButton(
            onPressed: () {
              try {
                Navigator.pop(
                  context,
                  Itemization.owedAmounts(
                    items: items,
                    assignments: _assignments,
                    taxMinor: widget.draft.taxMinor,
                    tipMinor: widget.draft.tipMinor,
                  ),
                );
              } on SplitException catch (e) {
                setState(() => _error = e.message);
              }
            },
            child: const Text('Done'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          for (var i = 0; i < items.length; i++)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          items[i].name,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      Text(formatMinor(items[i].amountMinor, widget.currency)),
                    ],
                  ),
                  Wrap(
                    spacing: 6,
                    children: [
                      for (final entry in widget.people.entries)
                        FilterChip(
                          label: Text(entry.value),
                          selected: _assignments[i]!.contains(entry.key),
                          onSelected: (on) => setState(() {
                            on
                                ? _assignments[i]!.add(entry.key)
                                : _assignments[i]!.remove(entry.key);
                            _error = null;
                          }),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          const Divider(height: 32),
          if (widget.draft.taxMinor + widget.draft.tipMinor > 0)
            ListTile(
              dense: true,
              title: const Text('Tax & tip'),
              subtitle: const Text('Shared in proportion to items'),
              trailing: Text(
                formatMinor(
                  widget.draft.taxMinor + widget.draft.tipMinor,
                  widget.currency,
                ),
              ),
            ),
          if (totals != null)
            for (final entry in widget.people.entries)
              ListTile(
                dense: true,
                title: Text(entry.value),
                trailing: Text(
                  formatMinor(totals[entry.key] ?? 0, widget.currency),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
        ],
      ),
    );
  }
}
