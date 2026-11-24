import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';
import 'package:split_app/app/brand.dart';
import 'package:split_app/app/providers.dart';
import 'package:split_app/core/ui/ui.dart';
import 'package:split_app/features/ledger/data/ledger_repository.dart';
import 'package:split_app/features/ledger/domain/models.dart';
import 'package:split_app/features/premium/domain/pro_feature.dart';
import 'package:split_app/features/premium/presentation/pro_gate.dart';

/// Text friends receive when you share a group's invite.
String inviteMessage(Group group) =>
    'Join my group "${group.name}" on ${Brand.name} to split expenses.\n\n'
    'Open ${Brand.name} → Join a group → enter code: ${group.inviteCode}';

Future<void> shareInvite(BuildContext context, Group group) async {
  final box = context.findRenderObject() as RenderBox?;
  await SharePlus.instance.share(
    ShareParams(
      text: inviteMessage(group),
      subject: 'Join "${group.name}" on ${Brand.name}',
      sharePositionOrigin: box == null
          ? null
          : box.localToGlobal(Offset.zero) & box.size,
    ),
  );
}

/// Bottom sheet: members list, invite code, and adding people.
Future<void> showGroupPeopleSheet(
  BuildContext context,
  WidgetRef ref,
  String groupId,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => _GroupPeopleSheet(groupId: groupId),
);

class _GroupPeopleSheet extends ConsumerWidget {
  const new({required this.groupId});
  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final ledger = ref.watch(ledgerProvider).value;
    final group = ledger?.group(groupId);
    if (ledger == null || group == null) return const SizedBox(height: 120);
    final code = group.inviteCode;

    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        children: [
          Text('People in ${group.name}', style: theme.textTheme.titleLarge),
          const SizedBox(height: 16),
          if (code != null) ...[
            DecoratedBox(
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Invite friends',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Send them this code. They sign in to ${Brand.name}, '
                      'tap "Join a group" and enter it.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: SelectableText(
                            code,
                            key: const Key('invite-code'),
                            style: theme.textTheme.headlineMedium?.copyWith(
                              letterSpacing: 4,
                              fontWeight: FontWeight.w700,
                              color: theme.colorScheme.onPrimaryContainer,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Copy code',
                          icon: const Icon(Icons.copy_rounded),
                          onPressed: () async {
                            await Clipboard.setData(ClipboardData(text: code));
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Code copied')),
                              );
                            }
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Builder(
                      builder: (context) => FilledButton.icon(
                        onPressed: () => shareInvite(context, group),
                        icon: const Icon(Icons.share_rounded),
                        label: const Text('Share invite'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          SectionCard(
            children: [
              for (final id in group.memberIds)
                ListTile(
                  leading: PersonAvatar(
                    id: id,
                    name: ledger.member(id).name,
                    size: 36,
                  ),
                  title: Text(
                    id == ledger.currentUserId
                        ? '${ledger.member(id).name} (you)'
                        : ledger.member(id).name,
                  ),
                  subtitle: ledger.member(id).isPlaceholder
                      ? const Text('Not on the app')
                      : null,
                ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.person_add_alt_rounded),
                title: const Text('Add someone not on the app'),
                trailing: const ProBadge(),
                onTap: () => _addPlaceholder(context, ref, group),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _addPlaceholder(
    BuildContext context,
    WidgetRef ref,
    Group group,
  ) async {
    if (!await ensurePro(context, ref, ProFeature.placeholderMembers)) return;
    if (!context.mounted) return;
    final name = await promptForText(
      context,
      title: 'Add a person',
      label: 'Name',
      action: 'Add',
    );
    if (name == null) return;
    final repo = ref.read(ledgerRepositoryProvider);
    final member = await repo.addMember(name: name, placeholder: true);
    await repo.addToGroup(groupId: group.id, personId: member.id);
  }
}

/// Asks for one line of text; returns it trimmed, or null if cancelled/empty.
Future<String?> promptForText(
  BuildContext context, {
  required String title,
  required String label,
  required String action,
  TextCapitalization capitalization = TextCapitalization.words,
}) async {
  final controller = TextEditingController();
  final result = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        textCapitalization: capitalization,
        decoration: InputDecoration(labelText: label),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(96, 44)),
          onPressed: () => Navigator.pop(context, controller.text),
          child: Text(action),
        ),
      ],
    ),
  );
  final trimmed = result?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

/// "Join a group" flow from the home screen. Returns the joined group id.
Future<String?> joinGroupFlow(BuildContext context, WidgetRef ref) async {
  final code = await promptForText(
    context,
    title: 'Join a group',
    label: 'Invite code',
    action: 'Join',
    capitalization: TextCapitalization.characters,
  );
  if (code == null || !context.mounted) return null;
  try {
    return await ref.read(ledgerRepositoryProvider).joinGroup(code);
  } on Object catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e is InvalidInviteCode || e is StateError
                ? e.toString().replaceFirst('Bad state: ', '')
                : "Couldn't join: $e",
          ),
        ),
      );
    }
    return null;
  }
}
