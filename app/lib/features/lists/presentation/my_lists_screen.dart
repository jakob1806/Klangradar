import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../application/event_lists_providers.dart';

class MyListsScreen extends ConsumerWidget {
  const MyListsScreen({super.key});

  Future<void> _createList(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.myListsCreateTitle),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: l10n.myListsNameHint),
          onSubmitted: (v) => Navigator.of(dialogContext).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.myListsCancel),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text),
            child: Text(l10n.myListsCreate),
          ),
        ],
      ),
    );
    if (name == null || name.trim().isEmpty || !context.mounted) return;

    final listId = await EventListsService.create(ref, name);
    if (listId != null && context.mounted) {
      context.push('/lists/$listId');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;
    final l10n = AppLocalizations.of(context)!;
    final user = ref.watch(currentUserProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.myListsAppBarTitle),
        actions: [
          if (user != null)
            IconButton(
              icon: const Icon(Icons.add_rounded),
              tooltip: l10n.myListsCreate,
              onPressed: () => _createList(context, ref),
            ),
        ],
      ),
      body: user == null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Text(
                  l10n.myListsSignInPrompt,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: colors.textSecondary),
                ),
              ),
            )
          : ref
                .watch(myEventListsProvider)
                .when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(
                    child: Text(
                      l10n.errorLoadingGeneric(e.toString()),
                      style: TextStyle(color: colors.error),
                    ),
                  ),
                  data: (lists) {
                    if (lists.isEmpty) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.xl),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                l10n.myListsEmptyState,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: colors.textSecondary,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.lg),
                              FilledButton(
                                onPressed: () => _createList(context, ref),
                                child: Text(l10n.myListsCreate),
                              ),
                            ],
                          ),
                        ),
                      );
                    }
                    return ListView.separated(
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.md,
                      ),
                      itemCount: lists.length,
                      separatorBuilder: (_, __) =>
                          Divider(height: 1, color: colors.separator),
                      itemBuilder: (context, index) {
                        final list = lists[index];
                        return ListTile(
                          leading: Icon(
                            Icons.playlist_play_rounded,
                            color: colors.accentPrimary,
                          ),
                          title: Text(
                            list.name,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: colors.textPrimary,
                            ),
                          ),
                          subtitle: Text(
                            l10n.myListsEventCount(list.events.length),
                            style: TextStyle(
                              color: colors.textSecondary,
                              fontSize: 12.5,
                            ),
                          ),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () => context.push('/lists/${list.id}'),
                        );
                      },
                    );
                  },
                ),
    );
  }
}
