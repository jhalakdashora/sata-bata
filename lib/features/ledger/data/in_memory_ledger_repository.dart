import 'dart:async';

import 'package:split_app/features/ledger/data/ledger_repository.dart';
import 'package:split_app/features/ledger/domain/models.dart';
import 'package:split_app/features/ledger/domain/recurrence.dart';
import 'package:uuid/uuid.dart';

/// Local, non-persistent repository. Used for demo mode (no Supabase keys)
/// and widget tests.
class InMemoryLedgerRepository implements LedgerRepository {
  new({LedgerSnapshot? seed}) : _state = seed ?? demoSeed();

  static const _uuid = Uuid();
  LedgerSnapshot _state;
  final _controller = StreamController<LedgerSnapshot>.broadcast();

  @override
  Stream<LedgerSnapshot> watch() async* {
    yield _state;
    yield* _controller.stream;
  }

  void _emit(LedgerSnapshot next) {
    _state = next;
    _controller.add(next);
  }

  LedgerSnapshot _copy({
    Map<String, Member>? members,
    List<Group>? groups,
    List<Expense>? expenses,
    Map<String, List<Comment>>? comments,
  }) => LedgerSnapshot(
    currentUserId: _state.currentUserId,
    members: members ?? _state.members,
    groups: groups ?? _state.groups,
    expenses: expenses ?? _state.expenses,
    comments: comments ?? _state.comments,
  );

  @override
  Future<String> uploadReceipt(String localFilePath) async => localFilePath;

  @override
  Future<Uri> receiptUri(String receiptPath) async => Uri.file(receiptPath);

  @override
  Future<void> addComment({
    required String expenseId,
    required String content,
  }) async {
    final comment = Comment(
      id: _uuid.v4(),
      expenseId: expenseId,
      authorId: _state.currentUserId,
      content: content,
      createdAt: DateTime.now(),
    );
    _emit(
      _copy(
        comments: {
          ..._state.comments,
          expenseId: [..._state.commentsFor(expenseId), comment],
        },
      ),
    );
  }

  @override
  Future<void> materializeRecurring(DateTime now) async {
    final existing = {for (final e in _state.expenses) e.id};
    final generated = [
      for (final template in _state.expenses.where((e) => e.isRecurring))
        ...Recurrence.materialize(
          template,
          now: now,
        ).where((e) => !existing.contains(e.id)),
    ];
    if (generated.isNotEmpty) {
      _emit(_copy(expenses: [...generated, ..._state.expenses]));
    }
  }

  @override
  Future<void> refresh() async => _emit(_state);

  @override
  Future<void> addExpense(Expense expense) async =>
      _emit(_copy(expenses: [expense, ..._state.expenses]));

  @override
  Future<void> deleteExpense(String expenseId) async => _emit(
    _copy(expenses: _state.expenses.where((e) => e.id != expenseId).toList()),
  );

  @override
  Future<Group> createGroup({
    required String name,
    required GroupType type,
    required List<String> memberIds,
  }) async {
    final group = Group(
      id: _uuid.v4(),
      name: name,
      type: type,
      memberIds: {_state.currentUserId, ...memberIds}.toList(),
      inviteCode: _uuid.v4().replaceAll('-', '').substring(0, 8).toUpperCase(),
    );
    _emit(_copy(groups: [..._state.groups, group]));
    return group;
  }

  @override
  Future<void> updateGroup(Group group) async => _emit(
    _copy(
      groups: [
        for (final g in _state.groups)
          if (g.id == group.id) group else g,
      ],
    ),
  );

  @override
  Future<void> deleteGroup(String groupId) async => _emit(
    _copy(
      groups: _state.groups.where((g) => g.id != groupId).toList(),
      expenses: _state.expenses.where((e) => e.groupId != groupId).toList(),
    ),
  );

  @override
  Future<String> joinGroup(String code) async {
    final normalized = code.toUpperCase().replaceAll(RegExp('[^A-Z0-9]'), '');
    final group = _state.groups.firstWhere(
      (g) => g.inviteCode == normalized,
      orElse: () => throw const InvalidInviteCode(),
    );
    return group.id;
  }

  @override
  Future<void> addToGroup({
    required String groupId,
    required String personId,
  }) async => _emit(
    _copy(
      groups: [
        for (final g in _state.groups)
          if (g.id == groupId && !g.memberIds.contains(personId))
            g.copyWith(memberIds: [...g.memberIds, personId])
          else
            g,
      ],
    ),
  );

  @override
  Future<Member> addMember({
    required String name,
    String? email,
    bool placeholder = false,
  }) async {
    final member = Member(
      id: _uuid.v4(),
      name: name,
      email: email,
      isPlaceholder: placeholder,
    );
    _emit(_copy(members: {..._state.members, member.id: member}));
    return member;
  }

  Future<void> dispose() => _controller.close();

  static LedgerSnapshot demoSeed() {
    const me = Member(id: 'me', name: 'You', email: 'you@example.com');
    const alex = Member(id: 'alex', name: 'Alex');
    const sam = Member(id: 'sam', name: 'Sam');
    const priya = Member(id: 'priya', name: 'Priya');
    final now = DateTime.now();
    return LedgerSnapshot(
      currentUserId: me.id,
      comments: {
        'e2': [
          Comment(
            id: 'c1',
            expenseId: 'e2',
            authorId: 'alex',
            content: 'Includes the oat milk 🥛',
            createdAt: now.subtract(const Duration(days: 2)),
          ),
        ],
      },
      members: {
        for (final m in [me, alex, sam, priya]) m.id: m,
      },
      groups: const [
        Group(
          id: 'g-flat',
          name: 'Flat 4B',
          type: GroupType.home,
          memberIds: ['me', 'alex', 'sam'],
          inviteCode: 'FLAT4B23',
        ),
        Group(
          id: 'g-goa',
          name: 'Goa trip',
          type: GroupType.trip,
          memberIds: ['me', 'alex', 'priya'],
          inviteCode: 'GOA7TRIP',
        ),
      ],
      expenses: [
        Expense(
          id: 'e1',
          groupId: 'g-flat',
          description: 'Rent',
          totalMinor: 4500000,
          currency: 'INR',
          paid: const {'me': 4500000},
          owed: const {'me': 1500000, 'alex': 1500000, 'sam': 1500000},
          date: now.subtract(const Duration(days: 5)),
          createdBy: 'me',
          category: 'Rent',
          repeat: RepeatInterval.monthly,
        ),
        Expense(
          id: 'e2',
          groupId: 'g-flat',
          description: 'Groceries',
          totalMinor: 245050,
          currency: 'INR',
          paid: const {'alex': 245050},
          owed: const {'me': 81684, 'alex': 81683, 'sam': 81683},
          date: now.subtract(const Duration(days: 2)),
          createdBy: 'alex',
          category: 'Groceries',
        ),
        Expense(
          id: 'e3',
          groupId: 'g-goa',
          description: 'Beach shack dinner',
          totalMinor: 360000,
          currency: 'INR',
          paid: const {'priya': 360000},
          owed: const {'me': 120000, 'alex': 120000, 'priya': 120000},
          date: now.subtract(const Duration(days: 1)),
          createdBy: 'priya',
          category: 'Dining out',
        ),
      ],
    );
  }
}
