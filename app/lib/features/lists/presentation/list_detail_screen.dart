import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/genre_artwork.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../application/event_lists_providers.dart';
import 'event_picker_screen.dart';

class ListDetailScreen extends ConsumerWidget {
  const ListDetailScreen({required this.listId, super.key});

  final String listId;

  Future<void> _rename(
    BuildContext context,
    WidgetRef ref,
    String currentName,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController(text: currentName);
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.myListsRenameTitle),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.myListsCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: Text(l10n.myListsSave),
          ),
        ],
      ),
    );
    if (name == null || name.trim().isEmpty) return;
    await EventListsService.rename(ref, listId, name);
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.myListsDeleteConfirmTitle),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.myListsCancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.myListsDelete),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await EventListsService.delete(ref, listId);
    if (context.mounted) context.pop();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;
    final l10n = AppLocalizations.of(context)!;
    final listsAsync = ref.watch(myEventListsProvider);

    return listsAsync.when(
      loading: () => Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Text(
            l10n.errorLoadingGeneric(e.toString()),
            style: TextStyle(color: colors.error),
          ),
        ),
      ),
      data: (lists) {
        final list = lists.where((l) => l.id == listId).firstOrNull;
        if (list == null) {
          return Scaffold(
            appBar: AppBar(),
            body: Center(child: Text(l10n.myListsNotFound)),
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: Text(list.name),
            actions: [
              // Nutzeranfrage: "oben rechts fehlt der Button" — öffnet den
              // Event-Picker zum Hinzufügen/Entfernen von Veranstaltungen.
              IconButton(
                icon: const Icon(Icons.add_rounded),
                tooltip: l10n.myListsAddEvents,
                onPressed: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => EventPickerScreen(
                        listId: listId,
                        currentEventIds: list.events.map((e) => e.id).toSet(),
                      ),
                    ),
                  );
                },
              ),
              PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'rename') _rename(context, ref, list.name);
                  if (value == 'delete') _delete(context, ref);
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'rename',
                    child: Text(l10n.myListsRename),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Text(l10n.myListsDelete),
                  ),
                ],
              ),
            ],
          ),
          body: Column(
            children: [
              _CoverEditor(listId: listId, coverImageUrl: list.coverImageUrl),
              Expanded(
                child: list.events.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.xl),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                l10n.myListsListEmptyState,
                                textAlign: TextAlign.center,
                                style: TextStyle(color: colors.textSecondary),
                              ),
                              const SizedBox(height: AppSpacing.lg),
                              FilledButton.icon(
                                icon: const Icon(Icons.add_rounded),
                                label: Text(l10n.myListsAddEvents),
                                onPressed: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => EventPickerScreen(
                                      listId: listId,
                                      currentEventIds: const {},
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.md,
                        ),
                        itemCount: list.events.length,
                        separatorBuilder: (_, __) =>
                            Divider(height: 1, color: colors.separator),
                        itemBuilder: (context, index) {
                          final e = list.events[index];
                          return ListTile(
                            leading: SizedBox(
                              width: 48,
                              height: 48,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: e.imageUrl != null
                                    ? CachedNetworkImage(
                                        imageUrl: e.imageUrl!,
                                        fit: BoxFit.cover,
                                        memCacheWidth:
                                            (48 *
                                                    MediaQuery.devicePixelRatioOf(
                                                      context,
                                                    ))
                                                .round(),
                                        memCacheHeight:
                                            (48 *
                                                    MediaQuery.devicePixelRatioOf(
                                                      context,
                                                    ))
                                                .round(),
                                        errorWidget: (context, url, error) =>
                                            GenreArtwork(genre: e.genre),
                                        placeholder: (context, url) =>
                                            GenreArtwork(genre: e.genre),
                                      )
                                    : GenreArtwork(genre: e.genre),
                              ),
                            ),
                            title: Text(
                              e.title,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: colors.textPrimary,
                              ),
                            ),
                            subtitle: Text(
                              e.venueAndTime,
                              style: TextStyle(
                                color: colors.textSecondary,
                                fontSize: 12.5,
                              ),
                            ),
                            onTap: () => context.pushNamed(
                              'event-detail',
                              pathParameters: {'slug': e.slug},
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

/// Titelbild einer Liste — Nutzeranfrage: "gleiches Verhalten wie
/// redaktionelle Sammlungen, ... dass ihnen auch ein übergeordnetes Bild
/// zugeordnet werden kann". Ohne Bild ein dezenter Platzhalter mit
/// Hinzufügen-Hinweis, mit Bild ein Querformat-Header wie die Kacheln in
/// [MyListsHomeSection].
class _CoverEditor extends ConsumerStatefulWidget {
  const _CoverEditor({required this.listId, required this.coverImageUrl});

  final String listId;
  final String? coverImageUrl;

  @override
  ConsumerState<_CoverEditor> createState() => _CoverEditorState();
}

class _CoverEditorState extends ConsumerState<_CoverEditor> {
  bool _isWorking = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final l10n = AppLocalizations.of(context)!;

    return GestureDetector(
      onTap: _isWorking ? null : _showActions,
      child: Container(
        height: 140,
        width: double.infinity,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(color: colors.backgroundSecondary),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (widget.coverImageUrl != null)
              CachedNetworkImage(
                imageUrl: widget.coverImageUrl!,
                fit: BoxFit.cover,
                memCacheWidth:
                    (MediaQuery.sizeOf(context).width *
                            MediaQuery.devicePixelRatioOf(context))
                        .round(),
                memCacheHeight: (140 * MediaQuery.devicePixelRatioOf(context))
                    .round(),
              )
            else
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.add_photo_alternate_outlined,
                      color: colors.textTertiary,
                      size: 28,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      l10n.myListsAddCoverImage,
                      style: TextStyle(
                        color: colors.textTertiary,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
            if (widget.coverImageUrl != null)
              Positioned(
                right: 10,
                bottom: 10,
                child: CircleAvatar(
                  radius: 16,
                  backgroundColor: Colors.black.withValues(alpha: 0.45),
                  child: const Icon(
                    Icons.camera_alt_rounded,
                    size: 16,
                    color: Colors.white,
                  ),
                ),
              ),
            if (_isWorking)
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.4),
                  ),
                  child: const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _showActions() async {
    final l10n = AppLocalizations.of(context)!;
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_rounded),
              title: Text(l10n.myListsCoverFromLibrary),
              onTap: () {
                Navigator.pop(sheetContext);
                _pick();
              },
            ),
            if (widget.coverImageUrl != null)
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded),
                title: Text(l10n.myListsCoverRemove),
                textColor: Theme.of(context).colorScheme.error,
                iconColor: Theme.of(context).colorScheme.error,
                onTap: () async {
                  Navigator.pop(sheetContext);
                  setState(() => _isWorking = true);
                  await EventListsService.removeCoverImage(ref, widget.listId);
                  if (mounted) setState(() => _isWorking = false);
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _pick() async {
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 95,
        maxWidth: 3000,
        maxHeight: 3000,
      );
      if (picked == null) return;
      if (!mounted) return;

      final l10n = AppLocalizations.of(context)!;
      final cropped = await ImageCropper().cropImage(
        sourcePath: picked.path,
        compressFormat: ImageCompressFormat.jpg,
        compressQuality: 88,
        maxWidth: 1600,
        maxHeight: 900,
        aspectRatio: const CropAspectRatio(ratioX: 16, ratioY: 9),
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: l10n.myListsCoverCropTitle,
            lockAspectRatio: true,
          ),
          IOSUiSettings(
            title: l10n.myListsCoverCropTitle,
            aspectRatioLockEnabled: true,
            resetAspectRatioEnabled: false,
          ),
        ],
      );
      if (cropped == null) return;

      setState(() => _isWorking = true);
      final bytes = await cropped.readAsBytes();
      await EventListsService.setCoverImage(ref, widget.listId, bytes);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)!.myListsCoverError(error.toString()),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isWorking = false);
    }
  }
}
