import 'package:split_app/features/ledger/domain/models.dart';

/// Immutable view of everything the signed-in user can see.
class LedgerSnapshot {
  const new({
    required this.currentUserId,
    required this.members,
    required this.groups,
    required this.expenses,
    this.comments = const {},
  });

  final String currentUserId;
  final Map<String, Member> members;
  final List<Group> groups;
  final List<Expense> expenses;

  /// expenseId -> comments, oldest first.
  final Map<String, List<Comment>> comments;

  Expense? expense(String id) {
    for (final e in expenses) {
      if (e.id == id) return e;
    }
    return null;
  }

  List<Comment> commentsFor(String expenseId) =>
      comments[expenseId] ?? const [];

  Member member(String id) => members[id] ?? Member(id: id, name: 'Unknown');

  Group? group(String id) {
    for (final g in groups) {
      if (g.id == id) return g;
    }
    return null;
  }

  List<Expense> expensesForGroup(String groupId) =>
      expenses.where((e) => e.groupId == groupId).toList();

  /// Non-group expenses shared between the current user and [friendId].
  List<Expense> expensesWithFriend(String friendId) => expenses
      .where(
        (e) =>
            e.groupId == null &&
            e.participantIds.contains(friendId) &&
            e.participantIds.contains(currentUserId),
      )
      .toList();

  /// Everyone the current user shares a group or expense with.
  Set<String> get friendIds => {
    for (final g in groups) ...g.memberIds,
    for (final e in expenses) ...e.participantIds,
  }..remove(currentUserId);
}

/// Source of truth for ledger data. Implementations: in-memory (demo/tests)
/// and Supabase (production).
abstract interface class LedgerRepository {
  Stream<LedgerSnapshot> watch();

  /// Refetches now; completes once [watch] has emitted the fresh snapshot.
  Future<void> refresh();

  Future<void> addExpense(Expense expense);
  Future<void> deleteExpense(String expenseId);

  /// Uploads a receipt image and returns the stored path to put on the
  /// expense.
  Future<String> uploadReceipt(String localFilePath);

  /// A URI the app can display for a stored receipt (file or signed URL).
  Future<Uri> receiptUri(String receiptPath);

  Future<void> addComment({required String expenseId, required String content});

  /// Creates any recurring-expense occurrences that are due. Safe to call
  /// repeatedly (idempotent).
  Future<void> materializeRecurring(DateTime now);

  Future<Group> createGroup({
    required String name,
    required GroupType type,
    required List<String> memberIds,
  });
  Future<void> updateGroup(Group group);

  /// Deletes the group with all its expenses.
  Future<void> deleteGroup(String groupId);

  /// Joins the group whose invite code is [code]; returns its id.
  Future<String> joinGroup(String code);

  /// Adds an existing person (for example a new placeholder) to a group.
  Future<void> addToGroup({required String groupId, required String personId});

  /// Adds someone by name/email. With [placeholder] true (Pro) the person
  /// gets no invite until later.
  Future<Member> addMember({
    required String name,
    String? email,
    bool placeholder = false,
  });
}

/// No group matches the invite code the user typed.
class InvalidInviteCode implements Exception {
  const new();

  @override
  String toString() => 'No group with that code. Check it and try again.';
}
