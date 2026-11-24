import 'dart:io' show File;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:split_app/app/providers.dart';
import 'package:split_app/core/ui/ui.dart';
import 'package:split_app/features/ledger/data/ledger_repository.dart';
import 'package:split_app/features/ledger/domain/models.dart';
import 'package:split_app/features/ledger/presentation/widgets.dart';

class ExpenseDetailScreen extends ConsumerStatefulWidget {
  const new({super.key, required this.expenseId});
  final String expenseId;

  @override
  ConsumerState<ExpenseDetailScreen> createState() =>
      _ExpenseDetailScreenState();
}

class _ExpenseDetailScreenState extends ConsumerState<ExpenseDetailScreen> {
  final _comment = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _comment.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    try {
      await ref
          .read(ledgerRepositoryProvider)
          .addComment(expenseId: widget.expenseId, content: text);
      _comment.clear();
    } on Object catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not post comment: $e')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _delete(Expense e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete "${e.description}"?'),
        content: e.isRecurring
            ? const Text('Future repeats will stop. Past copies stay.')
            : null,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (!(ok ?? false)) return;
    await ref.read(ledgerRepositoryProvider).deleteExpense(e.id);
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final ledger = ref.watch(ledgerProvider).value;
    final expense = ledger?.expense(widget.expenseId);
    if (ledger == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (expense == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('This expense was deleted')),
      );
    }
    final theme = Theme.of(context);
    final comments = ledger.commentsFor(expense.id);

    final payer = expense.paid.keys.first;
    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            tooltip: 'Delete',
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: () => _delete(expense),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: PullToRefresh(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 16),
                children: [
                  // Header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                    child: Row(
                      children: [
                        CategoryIcon(
                          category: expense.isPayment
                              ? 'Payment'
                              : expense.category,
                          size: 64,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                expense.isPayment
                                    ? 'Payment'
                                    : expense.description,
                                style: theme.textTheme.titleLarge,
                              ),
                              Text(
                                formatMinor(
                                  expense.totalMinor,
                                  expense.currency,
                                ),
                                style: theme.textTheme.headlineMedium,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _MetaChip(
                          icon: Icons.event_rounded,
                          label: DateFormat.yMMMd().format(expense.date),
                        ),
                        if (!expense.isPayment)
                          _MetaChip(
                            icon: Icons.sell_outlined,
                            label: expense.category,
                          ),
                        if (expense.isRecurring)
                          _MetaChip(
                            icon: Icons.repeat_rounded,
                            label:
                                'Repeats ${expense.repeat.label.toLowerCase()}',
                          ),
                      ],
                    ),
                  ),
                  SectionHeader(
                    '${nameFor(ledger, payer, capital: true)} paid '
                    '${formatMinor(expense.totalMinor, expense.currency)}',
                  ),
                  SectionCard(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    children: [
                      for (final id in expense.participantIds)
                        _ShareRow(
                          expense: expense,
                          ledger: ledger,
                          memberId: id,
                        ),
                    ],
                  ),
                  if (expense.receiptPath != null) ...[
                    const SectionHeader('Receipt'),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _ReceiptImage(path: expense.receiptPath!),
                    ),
                  ],
                  SectionHeader('Comments · ${comments.length}'),
                  if (comments.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Text(
                        'No comments yet. Say something!',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  for (final c in comments)
                    _CommentBubble(comment: c, ledger: ledger),
                ],
              ),
            ),
          ),
          Material(
            color: theme.colorScheme.surfaceContainer,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _comment,
                        minLines: 1,
                        maxLines: 4,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: InputDecoration(
                          hintText: 'Add a comment',
                          fillColor: theme.colorScheme.surface,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        onSubmitted: (_) => _send(),
                      ),
                    ),
                    const SizedBox(width: 4),
                    IconButton.filled(
                      tooltip: 'Send',
                      icon: const Icon(Icons.send_rounded),
                      onPressed: _sending ? null : _send,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const new({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(label, style: theme.textTheme.labelMedium),
        ],
      ),
    );
  }
}

class _ShareRow extends StatelessWidget {
  const new({
    required this.expense,
    required this.ledger,
    required this.memberId,
  });

  final Expense expense;
  final LedgerSnapshot ledger;
  final String memberId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final paid = expense.paid[memberId] ?? 0;
    final owed = expense.owed[memberId] ?? 0;
    final name = nameFor(ledger, memberId, capital: true);
    final parts = [
      if (paid > 0) 'paid ${formatMinor(paid, expense.currency)}',
      if (owed > 0)
        '${memberId == ledger.currentUserId ? 'owe' : 'owes'} ${formatMinor(owed, expense.currency)}',
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          PersonAvatar(
            id: memberId,
            name: ledger.member(memberId).name,
            size: 32,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '$name ${parts.join(' and ')}',
              style: theme.textTheme.bodyLarge,
            ),
          ),
        ],
      ),
    );
  }
}

class _CommentBubble extends StatelessWidget {
  const new({required this.comment, required this.ledger});
  final Comment comment;
  final LedgerSnapshot ledger;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final author = ledger.member(comment.authorId);
    final mine = comment.authorId == ledger.currentUserId;
    final time = DateFormat.MMMd().add_jm().format(comment.createdAt);
    if (comment.type == CommentType.system) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        child: Text(
          '${comment.content} · $time',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            fontStyle: FontStyle.italic,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    final bubble = Flexible(
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        decoration: BoxDecoration(
          color: mine
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${mine ? 'You' : author.name} · $time',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 2),
            Text(comment.content, style: theme.textTheme.bodyMedium),
          ],
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        mainAxisAlignment: mine
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!mine) ...[
            PersonAvatar(id: author.id, name: author.name, size: 28),
            const SizedBox(width: 8),
          ],
          bubble,
        ],
      ),
    );
  }
}

class _ReceiptImage extends ConsumerWidget {
  const new({required this.path});
  final String path;

  @override
  Widget build(BuildContext context, WidgetRef ref) => FutureBuilder<Uri>(
    future: ref.read(ledgerRepositoryProvider).receiptUri(path),
    builder: (context, snapshot) {
      final uri = snapshot.data;
      if (uri == null) {
        return const SizedBox(
          height: 120,
          child: Center(child: CircularProgressIndicator()),
        );
      }
      final Widget image = uri.scheme == 'file' && !kIsWeb
          ? Image.file(File(uri.toFilePath()), fit: BoxFit.cover)
          : Image.network(uri.toString(), fit: BoxFit.cover);
      return ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 320),
          child: image,
        ),
      );
    },
  );
}
