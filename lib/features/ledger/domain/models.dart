import 'package:collection/collection.dart';
import 'package:meta/meta.dart';
import 'package:split_app/core/money.dart';

/// A person who can take part in expenses. A placeholder member (a Pro
/// feature) has no account yet and can be invited later.
class Member {
  const new({
    required this.id,
    required this.name,
    this.email,
    this.isPlaceholder = false,
  });

  final String id;
  final String name;
  final String? email;
  final bool isPlaceholder;
}

enum GroupType { home, trip, couple, other }

class Group {
  const new({
    required this.id,
    required this.name,
    required this.memberIds,
    this.type = GroupType.other,
    this.simplifyDebts = true,
    this.defaultCurrency = AppCurrency.code,
    this.inviteCode,
  });

  final String id;
  final String name;
  final List<String> memberIds;
  final GroupType type;
  final bool simplifyDebts;
  final String defaultCurrency;

  /// Code friends enter to join this group. Null in demo mode.
  final String? inviteCode;

  Group copyWith({
    String? name,
    List<String>? memberIds,
    GroupType? type,
    bool? simplifyDebts,
    String? defaultCurrency,
  }) => Group(
    id: id,
    name: name ?? this.name,
    memberIds: memberIds ?? this.memberIds,
    type: type ?? this.type,
    simplifyDebts: simplifyDebts ?? this.simplifyDebts,
    defaultCurrency: defaultCurrency ?? this.defaultCurrency,
    inviteCode: inviteCode,
  );
}

enum SplitMethod { equal, exact, percent, shares, adjustment }

enum ExpenseKind { expense, payment }

enum RepeatInterval {
  never('Never'),
  weekly('Weekly'),
  fortnightly('Fortnightly'),
  monthly('Monthly'),
  yearly('Yearly');

  new(this.label);
  final String label;
}

enum CommentType { user, system }

/// A comment on an expense. System comments record changes ("Alex updated
/// the amount").
@immutable
class Comment {
  const new({
    required this.id,
    required this.expenseId,
    required this.authorId,
    required this.content,
    required this.createdAt,
    this.type = CommentType.user,
  });

  final String id;
  final String expenseId;
  final String authorId;
  final String content;
  final DateTime createdAt;
  final CommentType type;
}

/// One ledger entry. Payments (settle-ups) are stored as expenses of kind
/// [ExpenseKind.payment] where the payer "paid" and the recipient "owes" the
/// full amount, which keeps balance math uniform.
///
/// Invariant: sum(paid) == sum(owed) == totalMinor.
class Expense {
  new({
    required this.id,
    required this.description,
    required this.totalMinor,
    required this.currency,
    required this.paid,
    required this.owed,
    required this.date,
    required this.createdBy,
    this.groupId,
    this.category = 'General',
    this.kind = ExpenseKind.expense,
    this.splitMethod = SplitMethod.equal,
    this.notes,
    this.repeat = RepeatInterval.never,
    this.receiptPath,
  }) {
    final paidSum = paid.values.sum;
    final owedSum = owed.values.sum;
    if (paidSum != totalMinor || owedSum != totalMinor) {
      throw ArgumentError(
        'Expense "$description" is unbalanced: total=$totalMinor '
        'paid=$paidSum owed=$owedSum',
      );
    }
  }

  final String id;
  final String? groupId;
  final String description;
  final int totalMinor;
  final String currency;

  /// memberId -> minor units that member paid.
  final Map<String, int> paid;

  /// memberId -> minor units that member is responsible for.
  final Map<String, int> owed;
  final DateTime date;
  final String createdBy;
  final String category;
  final ExpenseKind kind;
  final SplitMethod splitMethod;
  final String? notes;

  /// For a recurring expense this is the template's interval; generated
  /// occurrences have [RepeatInterval.never].
  final RepeatInterval repeat;

  /// Storage path (or local file path in demo mode) of the receipt image.
  final String? receiptPath;

  bool get isPayment => kind == ExpenseKind.payment;
  bool get isRecurring => repeat != RepeatInterval.never;

  Expense copyWith({
    String? id,
    DateTime? date,
    RepeatInterval? repeat,
    String? description,
    String? notes,
  }) => Expense(
    id: id ?? this.id,
    groupId: groupId,
    description: description ?? this.description,
    totalMinor: totalMinor,
    currency: currency,
    paid: paid,
    owed: owed,
    date: date ?? this.date,
    createdBy: createdBy,
    category: category,
    kind: kind,
    splitMethod: splitMethod,
    notes: notes ?? this.notes,
    repeat: repeat ?? this.repeat,
    receiptPath: receiptPath,
  );

  Set<String> get participantIds => {...paid.keys, ...owed.keys};
}

/// A directed debt: [from] owes [to] [amountMinor].
@immutable
class Debt {
  const new({
    required this.from,
    required this.to,
    required this.amountMinor,
    required this.currency,
  });

  final String from;
  final String to;
  final int amountMinor;
  final String currency;

  @override
  bool operator ==(Object other) =>
      other is Debt &&
      other.from == from &&
      other.to == to &&
      other.amountMinor == amountMinor &&
      other.currency == currency;

  @override
  int get hashCode => Object.hash(from, to, amountMinor, currency);

  @override
  String toString() => 'Debt($from -> $to: $amountMinor $currency)';
}
