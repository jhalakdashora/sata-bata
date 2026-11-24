import 'dart:async';
import 'dart:io';

import 'package:split_app/core/money.dart';
import 'package:split_app/features/ledger/data/ledger_repository.dart';
import 'package:split_app/features/ledger/domain/models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

/// Supabase-backed ledger. Schema: supabase/migrations/0001_ledger.sql.
/// Strategy: fetch a full snapshot, then refetch whenever realtime reports a
/// change to a ledger table. RLS limits rows to what the user may see.
class SupabaseLedgerRepository implements LedgerRepository {
  new(this._db);

  final SupabaseClient _db;
  static const _uuid = Uuid();

  /// Refresh requests from [refresh]; each completer finishes after the
  /// matching fetch has been emitted.
  final _refreshRequests = StreamController<Completer<void>>.broadcast();

  /// Polling backs up realtime: fast while it's down, slow while it's up
  /// (in case events are silently not delivered).
  static const _pollWhileDown = Duration(seconds: 15);
  static const _pollWhileUp = Duration(seconds: 60);

  @override
  Future<void> refresh() {
    if (!_refreshRequests.hasListener) return Future.value();
    final done = Completer<void>();
    _refreshRequests.add(done);
    return done.future;
  }

  @override
  Stream<LedgerSnapshot> watch() {
    late final StreamController<LedgerSnapshot> controller;
    RealtimeChannel? channel;
    StreamSubscription<Completer<void>>? requests;
    Timer? debounce;
    Timer? poll;
    var latest = 0;

    Future<void> fetchAndEmit() async {
      // Only the newest fetch may emit, so a slow older response can't
      // overwrite fresher data.
      final seq = ++latest;
      try {
        final snapshot = await _fetch();
        if (seq == latest && !controller.isClosed) controller.add(snapshot);
      } on Object catch (e, st) {
        if (seq == latest && !controller.isClosed) controller.addError(e, st);
      }
    }

    void pollEvery(Duration interval) {
      poll?.cancel();
      poll = Timer.periodic(interval, (_) => unawaited(fetchAndEmit()));
    }

    controller = StreamController<LedgerSnapshot>(
      onListen: () {
        unawaited(fetchAndEmit());
        requests = _refreshRequests.stream.listen((done) async {
          await fetchAndEmit();
          if (!done.isCompleted) done.complete();
        });
        channel = _db.channel('ledger-changes');
        for (final table in [
          'expenses',
          'expense_shares',
          'expense_comments',
          'groups',
          'group_members',
        ]) {
          channel!.onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: table,
            callback: (_) {
              debounce?.cancel();
              debounce = Timer(
                const Duration(milliseconds: 250),
                () => unawaited(fetchAndEmit()),
              );
            },
          );
        }
        pollEvery(_pollWhileDown);
        channel!.subscribe((status, error) {
          if (status == RealtimeSubscribeStatus.subscribed) {
            pollEvery(_pollWhileUp);
            // Catch anything that changed while we were connecting.
            unawaited(fetchAndEmit());
          } else {
            pollEvery(_pollWhileDown);
          }
        });
      },
      onCancel: () async {
        debounce?.cancel();
        poll?.cancel();
        await requests?.cancel();
        if (channel != null) await _db.removeChannel(channel!);
      },
    );
    return controller.stream;
  }

  Future<LedgerSnapshot> _fetch() async {
    final me = await _db.rpc<String?>('my_person_id');
    if (me == null) throw StateError('Not signed in');

    final people = await _db.from('people').select();
    final groups = await _db
        .from('groups')
        .select('*, group_members(person_id)')
        .order('created_at');
    final expenses = await _db
        .from('expenses')
        .select('*, expense_shares(person_id, paid_minor, owed_minor)')
        .isFilter('deleted_at', null)
        .order('spent_at', ascending: false);
    final comments = await _db
        .from('expense_comments')
        .select()
        .isFilter('deleted_at', null)
        .order('created_at');

    final commentsByExpense = <String, List<Comment>>{};
    for (final c in comments) {
      final comment = Comment(
        id: c['id'] as String,
        expenseId: c['expense_id'] as String,
        authorId: c['author_id'] as String,
        content: c['content'] as String,
        createdAt: DateTime.parse(c['created_at'] as String),
        type: CommentType.values.byName(c['comment_type'] as String),
      );
      commentsByExpense.putIfAbsent(comment.expenseId, () => []).add(comment);
    }

    return LedgerSnapshot(
      comments: commentsByExpense,
      currentUserId: me,
      members: {
        for (final p in people)
          p['id'] as String: Member(
            id: p['id'] as String,
            name: p['display_name'] as String,
            email: p['email'] as String?,
            isPlaceholder: p['is_placeholder'] as bool,
          ),
      },
      groups: [
        for (final g in groups)
          Group(
            id: g['id'] as String,
            name: g['name'] as String,
            type: GroupType.values.byName(g['type'] as String),
            simplifyDebts: g['simplify_debts'] as bool,
            defaultCurrency: g['default_currency'] as String,
            inviteCode: g['invite_code'] as String?,
            memberIds: [
              for (final m in g['group_members'] as List)
                (m as Map)['person_id'] as String,
            ],
          ),
      ],
      expenses: [for (final e in expenses) _expenseFromRow(e)],
    );
  }

  Expense _expenseFromRow(Map<String, dynamic> e) {
    final shares = (e['expense_shares'] as List).cast<Map<String, dynamic>>();
    int asInt(Object? v) => (v! as num).toInt();
    return Expense(
      id: e['id'] as String,
      groupId: e['group_id'] as String?,
      description: e['description'] as String,
      totalMinor: asInt(e['total_minor']),
      currency: e['currency'] as String,
      category: e['category'] as String,
      kind: ExpenseKind.values.byName(e['kind'] as String),
      splitMethod: SplitMethod.values.byName(e['split_method'] as String),
      notes: e['notes'] as String?,
      date: DateTime.parse(e['spent_at'] as String),
      createdBy: e['created_by'] as String,
      repeat: RepeatInterval.values.byName(e['repeat_interval'] as String),
      receiptPath: e['receipt_path'] as String?,
      paid: {
        for (final s in shares)
          if (asInt(s['paid_minor']) > 0)
            s['person_id'] as String: asInt(s['paid_minor']),
      },
      owed: {
        for (final s in shares)
          if (asInt(s['owed_minor']) > 0)
            s['person_id'] as String: asInt(s['owed_minor']),
      },
    );
  }

  @override
  Future<void> addExpense(Expense expense) async {
    await _db.rpc<String>(
      'add_expense',
      params: {
        'payload': {
          'id': expense.id,
          'group_id': expense.groupId,
          'description': expense.description,
          'total_minor': expense.totalMinor,
          'currency': expense.currency,
          'category': expense.category,
          'kind': expense.kind.name,
          'split_method': expense.splitMethod.name,
          'notes': expense.notes,
          'spent_at': expense.date.toUtc().toIso8601String(),
          'repeat_interval': expense.repeat.name,
          'receipt_path': expense.receiptPath,
          'shares': [
            for (final id in expense.participantIds)
              {
                'person_id': id,
                'paid_minor': expense.paid[id] ?? 0,
                'owed_minor': expense.owed[id] ?? 0,
              },
          ],
        },
      },
    );
    await refresh();
  }

  @override
  Future<String> uploadReceipt(String localFilePath) async {
    final userId = _db.auth.currentUser?.id;
    if (userId == null) throw StateError('Not signed in');
    // Path starts with the uploader's id: storage policies key off it.
    final path = '$userId/${_uuid.v4()}.jpg';
    await _db.storage
        .from('receipts')
        .upload(
          path,
          File(localFilePath),
          fileOptions: const FileOptions(contentType: 'image/jpeg'),
        );
    return path;
  }

  @override
  Future<Uri> receiptUri(String receiptPath) async => Uri.parse(
    await _db.storage.from('receipts').createSignedUrl(receiptPath, 3600),
  );

  @override
  Future<void> addComment({
    required String expenseId,
    required String content,
  }) async {
    await _db.from('expense_comments').insert({
      'expense_id': expenseId,
      'content': content,
    });
    await refresh();
  }

  @override
  Future<void> materializeRecurring(DateTime now) async {
    final created = await _db.rpc<int>('materialize_recurring_expenses');
    if (created > 0) await refresh();
  }

  @override
  Future<void> deleteExpense(String expenseId) async {
    await _db
        .from('expenses')
        .update({'deleted_at': DateTime.now().toUtc().toIso8601String()})
        .eq('id', expenseId);
    await refresh();
  }

  @override
  Future<Group> createGroup({
    required String name,
    required GroupType type,
    required List<String> memberIds,
  }) async {
    final me = await _db.rpc<String>('my_person_id');
    final id = _uuid.v4();
    await _db.from('groups').insert({
      'id': id,
      'name': name,
      'type': type.name,
      'default_currency': AppCurrency.code,
    });
    final members = {me, ...memberIds}.toList();
    await _db.from('group_members').insert([
      for (final m in members) {'group_id': id, 'person_id': m},
    ]);
    await refresh();
    return Group(id: id, name: name, type: type, memberIds: members);
  }

  @override
  Future<void> updateGroup(Group group) async {
    // select() makes a silently-blocked update (0 rows) visible as an error.
    final rows = await _db
        .from('groups')
        .update({
          'name': group.name,
          'type': group.type.name,
          'simplify_debts': group.simplifyDebts,
          'default_currency': group.defaultCurrency,
        })
        .eq('id', group.id)
        .select('id');
    await refresh();
    if (rows.isEmpty) {
      throw StateError("You don't have permission to change this group.");
    }
  }

  @override
  Future<void> deleteGroup(String groupId) async {
    await _db.from('groups').delete().eq('id', groupId);
    await refresh();
  }

  @override
  Future<String> joinGroup(String code) async {
    try {
      final id = await _db.rpc<String>('join_group', params: {'code': code});
      await refresh();
      return id;
    } on PostgrestException catch (e) {
      if (e.code == 'P0002') throw const InvalidInviteCode();
      if (e.code == 'PGRST202') {
        throw StateError(
          'Joining groups needs a database update: run '
          'supabase/migrations/0005_invites_delete_groups.sql in Supabase.',
        );
      }
      rethrow;
    }
  }

  @override
  Future<void> addToGroup({
    required String groupId,
    required String personId,
  }) async {
    await _db.from('group_members').upsert({
      'group_id': groupId,
      'person_id': personId,
    }, ignoreDuplicates: true);
    await refresh();
  }

  @override
  Future<Member> addMember({
    required String name,
    String? email,
    bool placeholder = false,
  }) async {
    final row = await _db
        .from('people')
        .insert({
          'display_name': name,
          'email': email,
          'is_placeholder': placeholder,
        })
        .select()
        .single();
    return Member(
      id: row['id'] as String,
      name: name,
      email: email,
      isPlaceholder: placeholder,
    );
  }
}
