import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:split_app/app/brand.dart';
import 'package:split_app/app/providers.dart';
import 'package:split_app/app/theme.dart';
import 'package:split_app/core/ui/ui.dart';
import 'package:split_app/features/auth/data/auth_repository.dart';
import 'package:split_app/features/ledger/data/ledger_repository.dart';
import 'package:split_app/features/ledger/domain/balance_calculator.dart';
import 'package:split_app/features/ledger/domain/models.dart';
import 'package:split_app/features/ledger/presentation/group_people_sheet.dart';
import 'package:split_app/features/ledger/presentation/widgets.dart';
import 'package:split_app/features/premium/domain/pro_feature.dart';
import 'package:split_app/features/premium/presentation/pro_gate.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _tab = 0;

  static const _titles = ['Groups', 'Friends', 'Activity', 'Account'];

  @override
  Widget build(BuildContext context) {
    final ledger = ref.watch(ledgerProvider);
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 64,
        title: Text(
          _tab == 0 ? Brand.name : _titles[_tab],
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        actions: [
          IconButton(
            tooltip: 'Search',
            icon: const Icon(Icons.search_rounded),
            onPressed: () async {
              if (await ensurePro(context, ref, ProFeature.search) &&
                  context.mounted) {
                final data = ledger.value;
                if (data == null) return;
                await showSearch<void>(
                  context: context,
                  delegate: _ExpenseSearch(data),
                );
              }
            },
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: PullToRefresh(
        child: ledger.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ScrollableFill(
            child: EmptyState(
              icon: Icons.cloud_off_rounded,
              title: 'Could not load your data',
              message: '$e',
            ),
          ),
          data: (data) => switch (_tab) {
            0 => _GroupsTab(ledger: data),
            1 => _FriendsTab(ledger: data),
            2 => _ActivityTab(ledger: data),
            _ => _AccountTab(ledger: data),
          },
        ),
      ),
      floatingActionButton: _tab < 3
          ? FloatingActionButton.extended(
              onPressed: () => context.push('/expenses/new'),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add expense'),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.groups_outlined),
            selectedIcon: Icon(Icons.groups_rounded),
            label: 'Groups',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded),
            label: 'Friends',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long_rounded),
            label: 'Activity',
          ),
          NavigationDestination(
            icon: Icon(Icons.account_circle_outlined),
            selectedIcon: Icon(Icons.account_circle_rounded),
            label: 'Account',
          ),
        ],
      ),
    );
  }
}

String _plural(int n, String noun) => '$n $noun${n == 1 ? '' : 's'}';

/// currency -> minor for the current user, from a set of expenses.
Map<String, int> _myBalances(Iterable<Expense> expenses, String me) => {
  for (final e in BalanceCalculator.netBalances(expenses).entries)
    if ((e.value[me] ?? 0) != 0) e.key: e.value[me]!,
};

class _GroupsTab extends ConsumerWidget {
  const new({required this.ledger});
  final LedgerSnapshot ledger;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ledger.currentUserId;
    return ListView(
      padding: const EdgeInsets.only(bottom: 112),
      children: [
        _OverallCard(balances: _myBalances(ledger.expenses, me)),
        SectionHeader('Your groups · ${ledger.groups.length}'),
        if (ledger.groups.isEmpty)
          const EmptyState(
            icon: Icons.groups_rounded,
            title: 'No groups yet',
            message: 'Create a group for your home, a trip or anything shared.',
          )
        else
          SectionCard(
            children: [
              for (final (i, g) in ledger.groups.indexed) ...[
                if (i > 0) const Divider(indent: 80),
                ListTile(
                  leading: GroupIcon(group: g),
                  title: Text(g.name),
                  subtitle: Text(
                    '${_plural(g.memberIds.length, 'member')} · '
                    '${_plural(ledger.expensesForGroup(g.id).length, 'expense')}',
                  ),
                  trailing: BalanceSummary(
                    balances: _myBalances(ledger.expensesForGroup(g.id), me),
                  ),
                  onTap: () => context.push('/groups/${g.id}'),
                ),
              ],
            ],
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _createGroup(context, ref),
                  icon: const Icon(Icons.group_add_rounded),
                  label: const Text('New group'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final id = await joinGroupFlow(context, ref);
                    if (id != null && context.mounted) {
                      await context.push('/groups/$id');
                    }
                  },
                  icon: const Icon(Icons.login_rounded),
                  label: const Text('Join a group'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _createGroup(BuildContext context, WidgetRef ref) async {
    if (_creatingGroup) return;
    final name = TextEditingController();
    var type = GroupType.home;
    final friends = ledger.friendIds.toList();
    final selected = <String>{};
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('New group'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: name,
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Group name'),
                ),
                const SizedBox(height: 16),
                Text('Type', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final t in GroupType.values)
                      ChoiceChip(
                        avatar: Icon(groupTypeIcon(t), size: 18),
                        label: Text(
                          t.name[0].toUpperCase() + t.name.substring(1),
                        ),
                        selected: type == t,
                        showCheckmark: false,
                        onSelected: (_) => setState(() => type = t),
                      ),
                  ],
                ),
                if (friends.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Members',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  for (final id in friends)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      secondary: PersonAvatar(
                        id: id,
                        name: ledger.member(id).name,
                        size: 32,
                      ),
                      value: selected.contains(id),
                      title: Text(ledger.member(id).name),
                      onChanged: (v) => setState(
                        () => v! ? selected.add(id) : selected.remove(id),
                      ),
                    ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(96, 44)),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
    final groupName = name.text.trim();
    if (ok != true || groupName.isEmpty || !context.mounted) return;

    final existing = ledger.groups.firstWhereOrNull(
      (g) => g.name.toLowerCase() == groupName.toLowerCase(),
    );
    if (existing != null) {
      final open = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('You already have "${existing.name}"'),
          content: const Text('Open that group instead of making a copy?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Create anyway'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(96, 44)),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Open it'),
            ),
          ],
        ),
      );
      if (!context.mounted || open == null) return;
      if (open) {
        await context.push('/groups/${existing.id}');
        return;
      }
    }

    // Guard against a second tap while the first create is still saving.
    if (_creatingGroup) return;
    _creatingGroup = true;
    try {
      final group = await ref
          .read(ledgerRepositoryProvider)
          .createGroup(
            name: groupName,
            type: type,
            memberIds: selected.toList(),
          );
      if (context.mounted) await context.push('/groups/${group.id}');
    } on Object catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Couldn't create the group: $e")),
        );
      }
    } finally {
      _creatingGroup = false;
    }
  }
}

bool _creatingGroup = false;

/// Hero card with the user's overall position.
class _OverallCard extends StatelessWidget {
  const new({required this.balances});
  final Map<String, int> balances;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    const onHero = Colors.white;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Brand.seedColor,
              Color.lerp(Brand.seedColor, const Color(0xFF0B2E4A), 0.6)!,
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: scheme.shadow.withValues(alpha: 0.12),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.account_balance_wallet_rounded,
                    color: onHero.withValues(alpha: 0.85),
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Overall',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: onHero.withValues(alpha: 0.85),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (balances.isEmpty)
                Text(
                  "You're all settled up",
                  style: theme.textTheme.headlineSmall?.copyWith(color: onHero),
                ),
              for (final e in balances.entries) ...[
                Text(
                  e.value > 0 ? 'you are owed' : 'you owe',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: onHero.withValues(alpha: 0.8),
                  ),
                ),
                Text(
                  formatMinor(e.value.abs(), e.key),
                  style: theme.textTheme.headlineLarge?.copyWith(color: onHero),
                ),
                const SizedBox(height: 6),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _FriendsTab extends StatelessWidget {
  const new({required this.ledger});
  final LedgerSnapshot ledger;

  @override
  Widget build(BuildContext context) {
    final me = ledger.currentUserId;
    // Friend balances across all groups and non-group expenses.
    final debts = BalanceCalculator.pairwiseDebts(ledger.expenses);
    final perFriend = <String, Map<String, int>>{};
    for (final d in debts) {
      if (d.from != me && d.to != me) continue;
      final friend = d.from == me ? d.to : d.from;
      final sign = d.to == me ? 1 : -1;
      final bucket = perFriend.putIfAbsent(friend, () => {});
      bucket[d.currency] = (bucket[d.currency] ?? 0) + sign * d.amountMinor;
    }
    final friends = ledger.friendIds.sortedBy(
      (id) => ledger.member(id).name.toLowerCase(),
    );
    if (friends.isEmpty) {
      return const ScrollableFill(
        child: EmptyState(
          icon: Icons.person_add_alt_1_rounded,
          title: 'No friends yet',
          message:
              'Open a group and tap the add-person icon to invite friends. '
              'People you share groups with appear here.',
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.only(top: 4, bottom: 112),
      children: [
        SectionCard(
          children: [
            for (final (i, id) in friends.indexed) ...[
              if (i > 0) const Divider(indent: 72),
              ListTile(
                leading: PersonAvatar(id: id, name: ledger.member(id).name),
                title: Row(
                  children: [
                    Flexible(child: Text(ledger.member(id).name)),
                    if (ledger.member(id).isPlaceholder) ...[
                      const SizedBox(width: 8),
                      const Chip(
                        label: Text('placeholder'),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ],
                ),
                trailing: BalanceSummary(balances: perFriend[id] ?? const {}),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _ActivityTab extends ConsumerWidget {
  const new({required this.ledger});
  final LedgerSnapshot ledger;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ledger.expenses.isEmpty) {
      return const ScrollableFill(
        child: EmptyState(
          icon: Icons.receipt_long_rounded,
          title: 'No activity yet',
          message: 'Expenses and payments you add will show up here.',
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 112),
      children: monthGroupedExpenses(expenses: ledger.expenses, ledger: ledger),
    );
  }
}

class _AccountTab extends ConsumerWidget {
  const new({required this.ledger});
  final LedgerSnapshot ledger;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final entitlement = ref.watch(entitlementProvider).value;
    final isPro = entitlement?.isPro ?? false;
    final me = ledger.member(ledger.currentUserId);
    final canSignOut = ref.watch(authRepositoryProvider) is! DemoAuthRepository;

    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
          child: Row(
            children: [
              PersonAvatar(id: me.id, name: me.name, size: 64),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(me.name, style: theme.textTheme.titleLarge),
                    if (me.email != null)
                      Text(
                        me.email!,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: _ProCard(
            isPro: isPro,
            renews: entitlement?.expiresAt,
            onTap: () => context.push('/pro'),
          ),
        ),
        const SectionHeader('Preferences'),
        SectionCard(
          children: [
            const ListTile(
              leading: Icon(Icons.lock_outline_rounded),
              title: Text('App lock'),
              subtitle: Text('Coming soon: biometrics / device passcode'),
            ),
            const Divider(indent: 56),
            const ListTile(
              leading: Icon(Icons.notifications_none_rounded),
              title: Text('Notifications'),
              subtitle: Text('Coming soon'),
            ),
            if (canSignOut) ...[
              const Divider(indent: 56),
              ListTile(
                leading: Icon(
                  Icons.logout_rounded,
                  color: theme.colorScheme.error,
                ),
                title: Text(
                  'Sign out',
                  style: TextStyle(color: theme.colorScheme.error),
                ),
                onTap: () => ref.read(authRepositoryProvider).signOut(),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _ProCard extends StatelessWidget {
  const new({required this.isPro, required this.renews, required this.onTap});
  final bool isPro;
  final DateTime? renews;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const ink = Color(0xFF3B2600);
    return Material(
      borderRadius: BorderRadius.circular(AppTheme.radius),
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFFFD37A), Brand.proColor],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                const Icon(
                  Icons.workspace_premium_rounded,
                  color: ink,
                  size: 36,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isPro
                            ? '${Brand.proName}: active'
                            : 'Get ${Brand.proName}',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: ink,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        isPro && renews != null
                            ? 'Renews ${DateFormat.yMMMd().format(renews!)}'
                            : 'Receipt scanning, charts, search, export and more',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: ink.withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: ink),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ExpenseSearch extends SearchDelegate<void> {
  new(this.ledger);
  final LedgerSnapshot ledger;

  @override
  List<Widget> buildActions(BuildContext context) => [
    IconButton(
      icon: const Icon(Icons.clear_rounded),
      onPressed: () => query = '',
    ),
  ];

  @override
  Widget buildLeading(BuildContext context) =>
      BackButton(onPressed: () => close(context, null));

  @override
  Widget buildResults(BuildContext context) => _results();

  @override
  Widget buildSuggestions(BuildContext context) => _results();

  Widget _results() {
    final q = query.toLowerCase().trim();
    final hits = ledger.expenses.where(
      (e) =>
          q.isEmpty ||
          e.description.toLowerCase().contains(q) ||
          e.category.toLowerCase().contains(q) ||
          (e.notes?.toLowerCase().contains(q) ?? false),
    );
    if (hits.isEmpty) {
      return const EmptyState(
        icon: Icons.search_off_rounded,
        title: 'No matching expenses',
      );
    }
    return ListView(
      children: [for (final e in hits) ExpenseTile(expense: e, ledger: ledger)],
    );
  }
}
