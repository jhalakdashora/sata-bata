import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:split_app/app/providers.dart';
import 'package:split_app/core/money.dart';
import 'package:split_app/core/ui/ui.dart';
import 'package:split_app/features/ledger/data/ledger_repository.dart';
import 'package:split_app/features/ledger/domain/models.dart';
import 'package:split_app/features/ledger/domain/split_calculator.dart';
import 'package:split_app/features/premium/domain/pro_feature.dart';
import 'package:split_app/features/premium/presentation/pro_gate.dart';
import 'package:split_app/features/receipts/data/receipt_scanner.dart';
import 'package:split_app/features/receipts/domain/receipt_parser.dart';
import 'package:split_app/features/receipts/presentation/itemize_screen.dart';
import 'package:uuid/uuid.dart';

const _categories = [
  'General',
  'Groceries',
  'Dining out',
  'Rent',
  'Utilities',
  'Transportation',
  'Entertainment',
  'Hotel',
  'Gifts',
  'Medical expenses',
  'Other',
];

class AddExpenseScreen extends ConsumerStatefulWidget {
  const new({super.key, this.groupId});
  final String? groupId;

  @override
  ConsumerState<AddExpenseScreen> createState() => _AddExpenseScreenState();
}

class _AddExpenseScreenState extends ConsumerState<AddExpenseScreen> {
  final _description = TextEditingController();
  final _amount = TextEditingController();
  final _inputs = <String, TextEditingController>{};
  String? _groupId;
  String? _payerId;
  String _category = _categories.first;
  SplitMethod _method = SplitMethod.equal;
  Set<String> _participants = {};
  RepeatInterval _repeat = RepeatInterval.never;
  DateTime _date = DateTime.now();
  String? _receiptLocalPath;
  ReceiptDraft? _draft;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _groupId = widget.groupId;
  }

  @override
  void dispose() {
    _description.dispose();
    _amount.dispose();
    for (final c in _inputs.values) {
      c.dispose();
    }
    super.dispose();
  }

  List<String> _candidates(LedgerSnapshot l) {
    final g = _groupId == null ? null : l.group(_groupId!);
    return g?.memberIds ?? [l.currentUserId, ...l.friendIds];
  }

  String _currency(LedgerSnapshot l) =>
      (_groupId == null ? null : l.group(_groupId!)?.defaultCurrency) ??
      AppCurrency.code;

  TextEditingController _inputFor(String id) =>
      _inputs.putIfAbsent(id, TextEditingController.new);

  /// Converts the per-person text inputs into the integer units expected by
  /// [SplitCalculator] for the selected method.
  Map<String, int> _parsedInputs(String currency) {
    final result = <String, int>{};
    for (final id in _participants) {
      final text = _inputFor(id).text.trim();
      if (text.isEmpty) continue;
      result[id] = switch (_method) {
        SplitMethod.exact || SplitMethod.adjustment =>
          Money.tryParse(text, currency)?.minor ??
              (throw SplitException('Invalid amount "$text"')),
        SplitMethod.percent =>
          ((double.tryParse(text) ??
                      (throw SplitException('Invalid percent "$text"'))) *
                  100)
              .round(),
        SplitMethod.shares =>
          int.tryParse(text) ??
              (throw const SplitException('Shares must be whole numbers')),
        SplitMethod.equal => 0,
      };
    }
    return result;
  }

  Future<void> _save(LedgerSnapshot ledger) async {
    final currency = _currency(ledger);
    final amount = Money.tryParse(_amount.text, currency);
    setState(() => _error = null);
    if (_description.text.trim().isEmpty) {
      return setState(() => _error = 'Enter a description');
    }
    if (amount == null || !amount.isPositive) {
      return setState(() => _error = 'Enter a valid amount');
    }
    final payer = _payerId ?? ledger.currentUserId;
    setState(() => _saving = true);
    try {
      final owed = SplitCalculator.compute(
        totalMinor: amount.minor,
        participantIds: _participants.toList(),
        method: _method,
        inputs: _parsedInputs(currency),
      )..removeWhere((_, v) => v == 0);
      final repo = ref.read(ledgerRepositoryProvider);
      final receiptPath = _receiptLocalPath == null
          ? null
          : await repo.uploadReceipt(_receiptLocalPath!);
      await ref
          .read(ledgerRepositoryProvider)
          .addExpense(
            Expense(
              id: const Uuid().v4(),
              groupId: _groupId,
              description: _description.text.trim(),
              totalMinor: amount.minor,
              currency: currency,
              paid: {payer: amount.minor},
              owed: owed,
              date: _date,
              createdBy: ledger.currentUserId,
              category: _category,
              splitMethod: _method,
              repeat: _repeat,
              receiptPath: receiptPath,
            ),
          );
      if (mounted) context.pop();
    } on SplitException catch (e) {
      setState(() => _error = e.message);
    } on Object catch (e) {
      setState(() => _error = 'Could not save: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _scan() async {
    final entitlement = await ref.read(entitlementProvider.future);
    if (!mounted) return;
    if (!entitlement.canScanReceipt &&
        !await ensurePro(context, ref, ProFeature.receiptScanning)) {
      return;
    }
    if (!mounted) return;
    final source = await showModalBottomSheet<ReceiptSource>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!entitlement.isPro)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  '${entitlement.freeScansRemaining} free scans left',
                ),
              ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take photo'),
              onTap: () => Navigator.pop(context, ReceiptSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(context, ReceiptSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;

    final ScannedReceipt? result;
    try {
      result = await ref.read(receiptScannerProvider).scan(source);
    } on Object catch (e) {
      setState(() => _error = 'Scan failed: $e');
      return;
    }
    if (result == null || !mounted) return;
    if (!entitlement.isPro) {
      await ref.read(entitlementProvider.notifier).consumeFreeScan();
    }
    final draft = result.draft;
    setState(() {
      _receiptLocalPath = result!.imagePath;
      _draft = draft;
      if (_description.text.trim().isEmpty && draft.merchant != null) {
        _description.text = draft.merchant!;
      }
      if (draft.totalMinor != null) {
        _amount.text = (draft.totalMinor! / 100).toStringAsFixed(2);
      }
      if (draft.date != null) _date = draft.date!;
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            draft.totalMinor == null
                ? "Receipt attached, but we couldn't read a total"
                : 'Receipt scanned. Please check the details.',
          ),
        ),
      );
    }
  }

  Future<void> _itemize(LedgerSnapshot ledger) async {
    final draft = _draft;
    if (draft == null || draft.items.isEmpty) return;
    if (!await ensurePro(context, ref, ProFeature.itemization)) return;
    if (!mounted) return;
    final owed = await Navigator.of(context).push<Map<String, int>>(
      MaterialPageRoute(
        builder: (_) => ItemizeScreen(
          draft: draft,
          currency: _currency(ledger),
          people: {for (final id in _participants) id: ledger.member(id).name},
        ),
      ),
    );
    if (owed == null) return;
    setState(() {
      _method = SplitMethod.exact;
      final total = owed.values.fold<int>(0, (s, v) => s + v);
      _amount.text = (total / 100).toStringAsFixed(2);
      for (final id in _participants) {
        _inputFor(id).text = ((owed[id] ?? 0) / 100).toStringAsFixed(2);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final ledger = ref.watch(ledgerProvider).value;
    if (ledger == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final candidates = _candidates(ledger);
    if (_participants.isEmpty || !_participants.every(candidates.contains)) {
      _participants = candidates.toSet();
    }
    final payer = candidates.contains(_payerId)
        ? _payerId!
        : ledger.currentUserId;

    final theme = Theme.of(context);
    final hasItems = _draft?.items.isNotEmpty ?? false;
    const gap = SizedBox(height: 12);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Add expense'),
        actions: [
          IconButton(
            tooltip: 'Scan receipt',
            icon: const Icon(Icons.document_scanner_outlined),
            onPressed: _saving ? null : _scan,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          if (_error != null)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.error_outline_rounded,
                    color: theme.colorScheme.onErrorContainer,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          // Big amount entry
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Row(
              children: [
                CategoryIcon(category: _category, size: 56),
                const SizedBox(width: 14),
                Expanded(
                  child: TextField(
                    controller: _amount,
                    style: theme.textTheme.headlineLarge,
                    decoration: InputDecoration(
                      labelText: 'Amount',
                      prefixText:
                          '${_currency(ledger) == AppCurrency.code ? AppCurrency.symbol : _currency(ledger)} ',
                      prefixStyle: theme.textTheme.titleLarge?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      hintText: '0.00',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_receiptLocalPath != null) ...[
            SectionCard(
              children: [
                ListTile(
                  leading: const IconTile(
                    icon: Icons.receipt_long_rounded,
                    color: Color(0xFF607D8B),
                  ),
                  title: const Text('Receipt attached'),
                  subtitle: hasItems
                      ? Text('${_draft!.items.length} items found')
                      : null,
                  trailing: hasItems
                      ? FilledButton.tonalIcon(
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(0, 40),
                          ),
                          onPressed: () => _itemize(ledger),
                          icon: const ProBadge(),
                          label: const Text('Itemize'),
                        )
                      : IconButton(
                          tooltip: 'Remove receipt',
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => setState(() {
                            _receiptLocalPath = null;
                            _draft = null;
                          }),
                        ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          SectionCard(
            padding: const EdgeInsets.all(14),
            children: [
              TextField(
                controller: _description,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  prefixIcon: Icon(Icons.edit_note_rounded),
                ),
                textCapitalization: TextCapitalization.sentences,
              ),
              gap,
              DropdownButtonFormField<String?>(
                isExpanded: true,
                initialValue: _groupId,
                decoration: const InputDecoration(
                  labelText: 'Group',
                  prefixIcon: Icon(Icons.groups_rounded),
                ),
                items: [
                  const DropdownMenuItem(child: Text('No group (friends)')),
                  for (final g in ledger.groups)
                    DropdownMenuItem(value: g.id, child: Text(g.name)),
                ],
                onChanged: (v) => setState(() {
                  _groupId = v;
                  _participants = {};
                }),
              ),
              gap,
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: _category,
                decoration: const InputDecoration(
                  labelText: 'Category',
                  prefixIcon: Icon(Icons.sell_outlined),
                ),
                items: [
                  for (final c in _categories)
                    DropdownMenuItem(value: c, child: Text(c)),
                ],
                onChanged: (v) => setState(() => _category = v!),
              ),
            ],
          ),
          const SectionHeader('Paid by & when'),
          SectionCard(
            padding: const EdgeInsets.all(14),
            children: [
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: payer,
                decoration: const InputDecoration(
                  labelText: 'Paid by',
                  prefixIcon: Icon(Icons.account_balance_wallet_outlined),
                ),
                items: [
                  for (final id in candidates)
                    DropdownMenuItem(
                      value: id,
                      child: Text(
                        id == ledger.currentUserId
                            ? 'You'
                            : ledger.member(id).name,
                      ),
                    ),
                ],
                onChanged: (v) => setState(() => _payerId = v),
              ),
              gap,
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _date,
                          firstDate: DateTime(2000),
                          lastDate: DateTime.now().add(
                            const Duration(days: 365),
                          ),
                        );
                        if (picked != null) setState(() => _date = picked);
                      },
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Date',
                          prefixIcon: Icon(Icons.event_rounded),
                        ),
                        child: Text(DateFormat.yMMMd().format(_date)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<RepeatInterval>(
                      isExpanded: true,
                      initialValue: _repeat,
                      decoration: const InputDecoration(
                        labelText: 'Repeat',
                        prefixIcon: Icon(Icons.repeat_rounded),
                      ),
                      items: [
                        for (final r in RepeatInterval.values)
                          DropdownMenuItem(value: r, child: Text(r.label)),
                      ],
                      onChanged: (v) => setState(() => _repeat = v!),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SectionHeader('Split'),
          SectionCard(
            padding: const EdgeInsets.symmetric(vertical: 14),
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: SegmentedButton<SplitMethod>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: SplitMethod.equal, label: Text('=')),
                    ButtonSegment(
                      value: SplitMethod.exact,
                      label: Text('1.23'),
                    ),
                    ButtonSegment(value: SplitMethod.percent, label: Text('%')),
                    ButtonSegment(
                      value: SplitMethod.shares,
                      label: Text('shares'),
                    ),
                    ButtonSegment(
                      value: SplitMethod.adjustment,
                      label: Text('+/-'),
                    ),
                  ],
                  selected: {_method},
                  onSelectionChanged: (s) => setState(() => _method = s.first),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                child: Text(
                  _methodHelp(_method),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              for (final id in candidates)
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 2, 16, 2),
                  child: Row(
                    children: [
                      Checkbox(
                        value: _participants.contains(id),
                        onChanged: (v) => setState(
                          () => v!
                              ? _participants.add(id)
                              : _participants.remove(id),
                        ),
                      ),
                      PersonAvatar(
                        id: id,
                        name: ledger.member(id).name,
                        size: 32,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          ledger.member(id).name,
                          style: theme.textTheme.bodyLarge,
                        ),
                      ),
                      if (_method != SplitMethod.equal &&
                          _participants.contains(id))
                        SizedBox(
                          width: 104,
                          child: TextField(
                            controller: _inputFor(id),
                            textAlign: TextAlign.end,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: InputDecoration(
                              isDense: true,
                              hintText: '0',
                              suffixText: switch (_method) {
                                SplitMethod.percent => '%',
                                SplitMethod.shares => 'sh',
                                _ => null,
                              },
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: FilledButton(
            onPressed: _saving ? null : () => _save(ledger),
            child: _saving
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save'),
          ),
        ),
      ),
    );
  }
}

String _methodHelp(SplitMethod m) => switch (m) {
  SplitMethod.equal => 'Split equally between the selected people.',
  SplitMethod.exact => 'Specify exactly how much each person owes.',
  SplitMethod.percent => 'Enter percentages that add up to 100%.',
  SplitMethod.shares =>
    'Great for time-based splits (2 nights = 2 shares) or families.',
  SplitMethod.adjustment =>
    'Enter extra amounts per person; the rest is split equally.',
};
