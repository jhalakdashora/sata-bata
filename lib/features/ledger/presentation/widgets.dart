import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:split_app/app/providers.dart';
import 'package:split_app/core/money.dart';
import 'package:split_app/core/ui/ui.dart';
import 'package:split_app/features/ledger/data/ledger_repository.dart';
import 'package:split_app/features/ledger/domain/models.dart';

/// Pull down to refetch the ledger. Put it around a page body; the
/// scrollable inside gets overscroll even when its content is short. For
/// non-scrolling content (an empty state) use [ScrollableFill] inside it.
class PullToRefresh extends ConsumerWidget {
  const new({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) => RefreshIndicator(
    onRefresh: () => ref.read(ledgerRepositoryProvider).refresh(),
    child: ScrollConfiguration(
      behavior: const _AlwaysScrollable(),
      child: child,
    ),
  );
}

/// Makes non-scrolling content fill the page and accept pull-to-refresh.
class ScrollableFill extends StatelessWidget {
  const new({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => SingleChildScrollView(
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: constraints.maxHeight),
        child: Center(child: child),
      ),
    ),
  );
}

class _AlwaysScrollable extends MaterialScrollBehavior {
  const new();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics());
}

String formatMinor(int minor, String currency) =>
    Money(minor, currency).format();

/// Display name from the current user's point of view ("you" for self).
String nameFor(LedgerSnapshot ledger, String id, {bool capital = false}) {
  if (id == ledger.currentUserId) return capital ? 'You' : 'you';
  return ledger.member(id).name;
}

/// "you owe" / "you are owed" coloured amount line from the current user's
/// view.
class BalanceText extends StatelessWidget {
  const new({
    super.key,
    required this.minor,
    required this.currency,
    this.style,
  });

  /// Positive: user is owed. Negative: user owes.
  final int minor;
  final String currency;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final colors = context.money;
    if (minor == 0) {
      return Text(
        'settled up',
        style: (style ?? const TextStyle()).copyWith(color: colors.neutral),
      );
    }
    final owed = minor > 0;
    return Text(
      '${owed ? 'you are owed' : 'you owe'} '
      '${formatMinor(minor.abs(), currency)}',
      style: (style ?? const TextStyle()).copyWith(
        color: owed ? colors.owed : colors.owe,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

/// Right-aligned "you are owed / you owe" label for a per-currency balance
/// map (used by group and friend rows).
class BalanceSummary extends StatelessWidget {
  const new({super.key, required this.balances});

  /// currency -> minor (positive: owed to the user).
  final Map<String, int> balances;

  @override
  Widget build(BuildContext context) {
    final colors = context.money;
    final nonZero = balances.entries.where((e) => e.value != 0).toList();
    if (nonZero.isEmpty) {
      return Text(
        'settled up',
        style: Theme.of(context).textTheme.labelMedium
            ?.copyWith(color: colors.neutral),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (final e in nonZero)
          MoneyLabel(
            caption: e.value > 0 ? 'you are owed' : 'you owe',
            amount: formatMinor(e.value.abs(), e.key),
            color: e.value > 0 ? colors.owed : colors.owe,
          ),
      ],
    );
  }
}

/// Expenses grouped under month headers ("November 2026").
List<Widget> monthGroupedExpenses({
  required Iterable<Expense> expenses,
  required LedgerSnapshot ledger,
  void Function(Expense)? onLongPress,
}) {
  final sorted = expenses.sortedBy((e) => e.date).reversed;
  final out = <Widget>[];
  String? month;
  for (final e in sorted) {
    final m = DateFormat.yMMMM().format(e.date);
    if (m != month) {
      month = m;
      out.add(SectionHeader(m));
    }
    out.add(
      ExpenseTile(
        expense: e,
        ledger: ledger,
        onLongPress: onLongPress == null ? null : () => onLongPress(e),
      ),
    );
  }
  return out;
}

class ExpenseTile extends StatelessWidget {
  const new({
    super.key,
    required this.expense,
    required this.ledger,
    this.onLongPress,
  });

  final Expense expense;
  final LedgerSnapshot ledger;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.money;
    final me = ledger.currentUserId;
    final myNet = (expense.paid[me] ?? 0) - (expense.owed[me] ?? 0);

    final Widget title;
    final Widget subtitle;
    final Widget trailing;
    if (expense.isPayment) {
      final from = nameFor(ledger, expense.paid.keys.first, capital: true);
      final to = nameFor(ledger, expense.owed.keys.first);
      title = Text('$from paid $to');
      subtitle = const Text('Payment');
      trailing = Text(
        formatMinor(expense.totalMinor, expense.currency),
        style: theme.textTheme.titleSmall,
      );
    } else {
      final payers = expense.paid.keys
          .map((id) => nameFor(ledger, id, capital: true))
          .join(', ');
      title = Text(
        expense.description,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
      subtitle = Row(
        children: [
          if (expense.isRecurring) ...[
            Icon(
              Icons.repeat_rounded,
              size: 14,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              '$payers paid '
              '${formatMinor(expense.totalMinor, expense.currency)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      );
      trailing = myNet == 0
          ? Text(
              'not involved',
              style: theme.textTheme.labelMedium?.copyWith(
                color: colors.neutral,
              ),
            )
          : MoneyLabel(
              caption: myNet > 0 ? 'you lent' : 'you borrowed',
              amount: formatMinor(myNet.abs(), expense.currency),
              color: myNet > 0 ? colors.owed : colors.owe,
            );
    }

    return InkWell(
      onTap: () => context.push('/expenses/${expense.id}'),
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            SizedBox(
              width: 34,
              child: Column(
                children: [
                  Text(
                    DateFormat.MMM().format(expense.date).toUpperCase(),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    '${expense.date.day}',
                    style: theme.textTheme.titleMedium?.copyWith(height: 1.1),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            CategoryIcon(
              category: expense.isPayment ? 'Payment' : expense.category,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DefaultTextStyle.merge(
                    style: theme.textTheme.titleMedium,
                    child: title,
                  ),
                  const SizedBox(height: 2),
                  DefaultTextStyle.merge(
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    child: subtitle,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            trailing,
          ],
        ),
      ),
    );
  }
}
