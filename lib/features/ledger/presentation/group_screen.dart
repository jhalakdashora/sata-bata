import 'package:collection/collection.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:split_app/app/providers.dart';
import 'package:split_app/core/ui/ui.dart';
import 'package:split_app/features/ledger/data/ledger_repository.dart';
import 'package:split_app/features/ledger/domain/balance_calculator.dart';
import 'package:split_app/features/ledger/domain/models.dart';
import 'package:split_app/features/ledger/presentation/group_people_sheet.dart';
import 'package:split_app/features/ledger/presentation/widgets.dart';
import 'package:split_app/features/premium/domain/pro_feature.dart';
import 'package:split_app/features/premium/presentation/pro_gate.dart';

class GroupScreen extends ConsumerWidget {
  const new({super.key, required this.groupId});
  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ledger = ref.watch(ledgerProvider).value;
    final group = ledger?.group(groupId);
    if (ledger == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (group == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const PullToRefresh(
          child: ScrollableFill(
            child: EmptyState(
              icon: Icons.group_off_rounded,
              title: 'Group not found',
              message: 'It may have been deleted.',
            ),
          ),
        ),
      );
    }
    final theme = Theme.of(context);
    final expenses = ledger.expensesForGroup(groupId);
    final debts = BalanceCalculator.debtsFor(
      expenses,
      simplify: group.simplifyDebts,
    );
    final me = ledger.currentUserId;
    final myBalances = {
      for (final e in BalanceCalculator.netBalances(expenses).entries)
        if ((e.value[me] ?? 0) != 0) e.key: e.value[me]!,
    };

    return Scaffold(
      appBar: AppBar(
        title: Text(group.name),
        actions: [
          IconButton(
            tooltip: 'Add people',
            icon: const Icon(Icons.person_add_alt_1_rounded),
            onPressed: () => showGroupPeopleSheet(context, ref, groupId),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (v) => switch (v) {
              'totals' => _showTotals(context, ref, ledger, group),
              'export' => _export(context, ref, ledger, group),
              'delete' => _confirmDeleteGroup(context, ref, group),
              _ => null,
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'totals',
                child: Row(
                  children: [
                    Icon(Icons.pie_chart_outline_rounded),
                    SizedBox(width: 12),
                    Flexible(child: Text('Totals & charts')),
                    SizedBox(width: 8),
                    ProBadge(),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'export',
                child: Row(
                  children: [
                    Icon(Icons.ios_share_rounded),
                    SizedBox(width: 12),
                    Flexible(child: Text('Export CSV')),
                    SizedBox(width: 8),
                    ProBadge(),
                  ],
                ),
              ),
              PopupMenuDivider(),
              PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete_outline_rounded),
                    SizedBox(width: 12),
                    Text('Delete group'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: PullToRefresh(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 112),
          children: [
            // Header: icon, members, my position.
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Row(
                children: [
                  GroupIcon(group: group, size: 64),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AvatarStack(
                          people: {
                            for (final id in group.memberIds)
                              id: ledger.member(id).name,
                          },
                        ),
                        const SizedBox(height: 8),
                        if (myBalances.isEmpty)
                          Text(
                            "You're settled up in this group",
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          )
                        else
                          for (final e in myBalances.entries)
                            BalanceText(
                              minor: e.value,
                              currency: e.key,
                              style: theme.textTheme.titleMedium,
                            ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (group.memberIds.length < 2)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Card(
                  child: ListTile(
                    leading: const Icon(Icons.group_add_rounded),
                    title: const Text("It's just you here"),
                    subtitle: const Text('Invite friends to start splitting'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => showGroupPeopleSheet(context, ref, groupId),
                  ),
                ),
              ),
            const SectionHeader('Balances'),
            SectionCard(
              children: [
                if (debts.isEmpty)
                  const ListTile(
                    leading: Icon(Icons.check_circle_rounded),
                    title: Text('Everyone is settled up'),
                  )
                else
                  for (final d in debts) _DebtRow(debt: d, ledger: ledger),
                const Divider(),
                SwitchListTile(
                  secondary: const Icon(Icons.auto_awesome_rounded),
                  title: const Text('Simplify debts'),
                  subtitle: const Text(
                    'Combine debts so the group needs fewer payments',
                  ),
                  value: group.simplifyDebts,
                  onChanged: (v) async {
                    try {
                      await ref
                          .read(ledgerRepositoryProvider)
                          .updateGroup(group.copyWith(simplifyDebts: v));
                    } on Object catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              "Couldn't change this setting: "
                              '${e.toString().replaceFirst('Bad state: ', '')}',
                            ),
                          ),
                        );
                      }
                    }
                  },
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: FilledButton.icon(
                onPressed: debts.isEmpty
                    ? null
                    : () => context.push('/groups/$groupId/settle'),
                icon: const Icon(Icons.handshake_rounded),
                label: const Text('Settle up'),
              ),
            ),
            if (expenses.isEmpty)
              const EmptyState(
                icon: Icons.receipt_long_rounded,
                title: 'No expenses yet',
                message: 'Add the first expense to start splitting.',
              )
            else
              ...monthGroupedExpenses(
                expenses: expenses,
                ledger: ledger,
                onLongPress: (e) => _confirmDelete(context, ref, e),
              ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/expenses/new?groupId=$groupId'),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add expense'),
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    Expense e,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete "${e.description}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(96, 44)),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok ?? false) {
      await ref.read(ledgerRepositoryProvider).deleteExpense(e.id);
    }
  }

  Future<void> _confirmDeleteGroup(
    BuildContext context,
    WidgetRef ref,
    Group group,
  ) async {
    final count = ref
        .read(ledgerProvider)
        .value
        ?.expensesForGroup(group.id)
        .length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete "${group.name}"?'),
        content: Text(
          count == null || count == 0
              ? 'This removes the group for everyone in it.'
              : 'This removes the group and its $count '
                    '${count == 1 ? 'expense' : 'expenses'} for everyone '
                    "in it. This can't be undone.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size(96, 44),
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (!(ok ?? false) || !context.mounted) return;
    try {
      await ref.read(ledgerRepositoryProvider).deleteGroup(group.id);
      if (context.mounted) context.go('/');
    } on Object catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("Couldn't delete: $e")));
      }
    }
  }

  Future<void> _showTotals(
    BuildContext context,
    WidgetRef ref,
    LedgerSnapshot ledger,
    Group group,
  ) async {
    if (!await ensurePro(context, ref, ProFeature.charts)) return;
    if (!context.mounted) return;
    // currency -> category -> total
    final totals = <String, Map<String, int>>{};
    for (final e in ledger.expensesForGroup(group.id)) {
      if (e.isPayment) continue;
      final bucket = totals.putIfAbsent(e.currency, () => {});
      bucket[e.category] = (bucket[e.category] ?? 0) + e.totalMinor;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        final theme = Theme.of(context);
        return ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
          children: [
            Text('Group spending', style: theme.textTheme.titleLarge),
            for (final c in totals.entries) ...[
              const SizedBox(height: 16),
              Text(
                'Total spent',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              Text(
                formatMinor(c.value.values.sum, c.key),
                style: theme.textTheme.headlineMedium,
              ),
              const SizedBox(height: 12),
              for (final cat in c.value.entries.sortedBy((e) => -e.value))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      CategoryIcon(category: cat.key, size: 36),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    cat.key,
                                    style: theme.textTheme.titleSmall,
                                  ),
                                ),
                                Text(formatMinor(cat.value, c.key)),
                              ],
                            ),
                            const SizedBox(height: 6),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                minHeight: 8,
                                value: cat.value / c.value.values.sum,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        );
      },
    );
  }

  Future<void> _export(
    BuildContext context,
    WidgetRef ref,
    LedgerSnapshot ledger,
    Group group,
  ) async {
    if (!await ensurePro(context, ref, ProFeature.export)) return;
    String esc(String s) => '"${s.replaceAll('"', '""')}"';
    final members = group.memberIds;
    final rows = [
      [
        'Date',
        'Description',
        'Category',
        'Cost',
        'Currency',
        for (final m in members) ledger.member(m).name,
      ].map(esc).join(','),
      for (final e in ledger.expensesForGroup(group.id).sortedBy((e) => e.date))
        [
          esc(e.date.toIso8601String().split('T').first),
          esc(e.isPayment ? 'Payment' : e.description),
          esc(e.category),
          (e.totalMinor / 100).toStringAsFixed(2),
          e.currency,
          for (final m in members)
            (((e.paid[m] ?? 0) - (e.owed[m] ?? 0)) / 100).toStringAsFixed(2),
        ].join(','),
    ];
    await Clipboard.setData(ClipboardData(text: rows.join('\n')));
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('CSV copied to clipboard')));
    }
  }
}

/// "Sam → you  ₹528.16" with avatars.
class _DebtRow extends StatelessWidget {
  const new({required this.debt, required this.ledger});
  final Debt debt;
  final LedgerSnapshot ledger;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final me = ledger.currentUserId;
    final colors = context.money;
    final color = debt.to == me
        ? colors.owed
        : debt.from == me
        ? colors.owe
        : theme.colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          PersonAvatar(
            id: debt.from,
            name: ledger.member(debt.from).name,
            size: 32,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Icon(
              Icons.arrow_forward_rounded,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          PersonAvatar(
            id: debt.to,
            name: ledger.member(debt.to).name,
            size: 32,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '${nameFor(ledger, debt.from, capital: true)} '
              '${debt.from == me ? 'owe' : 'owes'} '
              '${nameFor(ledger, debt.to)}',
              style: theme.textTheme.bodyLarge,
            ),
          ),
          Text(
            formatMinor(debt.amountMinor, debt.currency),
            style: theme.textTheme.titleSmall?.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}
