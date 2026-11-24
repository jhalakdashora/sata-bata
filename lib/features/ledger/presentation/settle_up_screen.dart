import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:split_app/app/providers.dart';
import 'package:split_app/core/ui/ui.dart';
import 'package:split_app/features/ledger/domain/balance_calculator.dart';
import 'package:split_app/features/ledger/domain/models.dart';
import 'package:split_app/features/ledger/presentation/widgets.dart';
import 'package:uuid/uuid.dart';

/// Records a cash/external payment that settles a debt.
class SettleUpScreen extends ConsumerWidget {
  const new({super.key, required this.groupId});
  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ledger = ref.watch(ledgerProvider).value;
    final group = ledger?.group(groupId);
    if (ledger == null || group == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final theme = Theme.of(context);
    final colors = context.money;
    final me = ledger.currentUserId;
    final debts = BalanceCalculator.debtsFor(
      ledger.expensesForGroup(groupId),
      simplify: group.simplifyDebts,
    ).where((d) => d.from == me || d.to == me).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Settle up')),
      body: PullToRefresh(
        child: debts.isEmpty
            ? const ScrollableFill(
                child: EmptyState(
                  icon: Icons.celebration_rounded,
                  title: "You're all settled up in this group",
                ),
              )
            : ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                    child: Text(
                      'Record a payment you made or received outside the app '
                      '(cash, bank transfer, UPI…).',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  for (final d in debts)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              PersonAvatar(
                                id: d.from == me ? d.to : d.from,
                                name: ledger
                                    .member(d.from == me ? d.to : d.from)
                                    .name,
                                size: 48,
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      d.from == me
                                          ? 'You pay ${ledger.member(d.to).name}'
                                          : '${ledger.member(d.from).name} pays you',
                                      style: theme.textTheme.titleMedium,
                                    ),
                                    Text(
                                      formatMinor(d.amountMinor, d.currency),
                                      style: theme.textTheme.titleLarge
                                          ?.copyWith(
                                            color: d.from == me
                                                ? colors.owe
                                                : colors.owed,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                              FilledButton(
                                style: FilledButton.styleFrom(
                                  minimumSize: const Size(88, 44),
                                ),
                                child: const Text('Record'),
                                onPressed: () async {
                                  await ref
                                      .read(ledgerRepositoryProvider)
                                      .addExpense(
                                        Expense(
                                          id: const Uuid().v4(),
                                          groupId: groupId,
                                          description: 'Payment',
                                          totalMinor: d.amountMinor,
                                          currency: d.currency,
                                          paid: {d.from: d.amountMinor},
                                          owed: {d.to: d.amountMinor},
                                          date: DateTime.now(),
                                          createdBy: me,
                                          category: 'Payment',
                                          kind: ExpenseKind.payment,
                                        ),
                                      );
                                  if (context.mounted) context.pop();
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}
