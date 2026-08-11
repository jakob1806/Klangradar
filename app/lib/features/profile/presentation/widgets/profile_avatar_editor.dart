import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/theme/app_colors.dart';

final profileAvatarProvider = FutureProvider.autoDispose
    .family<String?, String>((ref, userId) async {
      final row = await Supabase.instance.client
          .from('profiles')
          .select('avatar_url')
          .eq('id', userId)
          .maybeSingle();
      return row?['avatar_url'] as String?;
    });

class ProfileAvatarEditor extends ConsumerStatefulWidget {
  const ProfileAvatarEditor({required this.userId, super.key});

  final String userId;

  @override
  ConsumerState<ProfileAvatarEditor> createState() =>
      _ProfileAvatarEditorState();
}

class _ProfileAvatarEditorState extends ConsumerState<ProfileAvatarEditor> {
  bool _isWorking = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final avatar = ref.watch(profileAvatarProvider(widget.userId));

    return Semantics(
      button: true,
      label: 'Profilbild bearbeiten',
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: _isWorking ? null : () => _showActions(avatar.valueOrNull),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            CircleAvatar(
              radius: 38,
              backgroundColor: colors.accentPrimary,
              backgroundImage: avatar.valueOrNull != null
                  ? NetworkImage(avatar.valueOrNull!)
                  : null,
              child: avatar.isLoading
                  ? const CircularProgressIndicator(color: Colors.white)
                  : avatar.valueOrNull == null
                  ? const Icon(
                      Icons.person_rounded,
                      color: Colors.white,
                      size: 34,
                    )
                  : null,
            ),
            Positioned(
              right: -2,
              bottom: -2,
              child: CircleAvatar(
                radius: 13,
                backgroundColor: colors.backgroundPrimary,
                child: Icon(
                  Icons.camera_alt_rounded,
                  size: 16,
                  color: colors.accentPrimary,
                ),
              ),
            ),
            if (_isWorking)
              const Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Color(0x66000000),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: SizedBox.square(
                      dimension: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _showActions(String? currentUrl) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_rounded),
              title: const Text('Aus Mediathek auswählen'),
              onTap: () {
                Navigator.pop(sheetContext);
                _pick(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_rounded),
              title: const Text('Foto aufnehmen'),
              onTap: () {
                Navigator.pop(sheetContext);
                _pick(ImageSource.camera);
              },
            ),
            if (currentUrl != null)
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded),
                title: const Text('Profilbild löschen'),
                textColor: Theme.of(context).colorScheme.error,
                iconColor: Theme.of(context).colorScheme.error,
                onTap: () {
                  Navigator.pop(sheetContext);
                  _confirmDelete();
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _pick(ImageSource source) async {
    try {
      final picked = await ImagePicker().pickImage(
        source: source,
        imageQuality: 95,
        maxWidth: 3000,
        maxHeight: 3000,
      );
      if (picked == null) return;

      final cropped = await ImageCropper().cropImage(
        sourcePath: picked.path,
        compressFormat: ImageCompressFormat.jpg,
        compressQuality: 88,
        maxWidth: 1200,
        maxHeight: 1200,
        aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Profilbild ausrichten',
            lockAspectRatio: true,
            hideBottomControls: false,
            initAspectRatio: CropAspectRatioPreset.square,
          ),
          IOSUiSettings(
            title: 'Profilbild ausrichten',
            aspectRatioLockEnabled: true,
            resetAspectRatioEnabled: false,
            rotateButtonsHidden: false,
            rotateClockwiseButtonHidden: false,
          ),
        ],
      );
      if (cropped == null) return;
      await _upload(File(cropped.path));
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _upload(File image) async {
    setState(() => _isWorking = true);
    try {
      final client = Supabase.instance.client;
      final path = '${widget.userId}/avatar.jpg';
      await client.storage
          .from('profile-avatars')
          .uploadBinary(
            path,
            await image.readAsBytes(),
            fileOptions: const FileOptions(
              contentType: 'image/jpeg',
              upsert: true,
              cacheControl: '3600',
            ),
          );
      final publicUrl = client.storage
          .from('profile-avatars')
          .getPublicUrl(path);
      final versionedUrl =
          '$publicUrl?v=${DateTime.now().millisecondsSinceEpoch}';
      await client
          .from('profiles')
          .update({'avatar_url': versionedUrl})
          .eq('id', widget.userId);
      ref.invalidate(profileAvatarProvider(widget.userId));
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _isWorking = false);
    }
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Profilbild löschen?'),
        content: const Text('Das aktuelle Profilbild wird dauerhaft entfernt.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Abbrechen'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _delete();
  }

  Future<void> _delete() async {
    setState(() => _isWorking = true);
    try {
      final client = Supabase.instance.client;
      await client.storage.from('profile-avatars').remove([
        '${widget.userId}/avatar.jpg',
      ]);
      await client
          .from('profiles')
          .update({'avatar_url': null})
          .eq('id', widget.userId);
      ref.invalidate(profileAvatarProvider(widget.userId));
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _isWorking = false);
    }
  }

  void _showError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Profilbild konnte nicht gespeichert werden: $error'),
      ),
    );
  }
}
