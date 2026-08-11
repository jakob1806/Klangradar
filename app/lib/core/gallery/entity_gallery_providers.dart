import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Bucket, in den ensureCoverImage() (backend/supabase/functions/_shared/
/// imagePipeline.ts) heruntergeladene/hochgeladene Bilder ablegt.
const _kImagesBucket = 'ingested-images';

/// Ein Galerie-Bild mit optionalem redaktionellem Querformat-Zuschnitt
/// (siehe Admin-Crop-Tool). `crop` ist bereits in ein [Rect] umgewandelt
/// (Anteile 0..1), passend zu [CroppedNetworkImage].
class GalleryImage {
  const GalleryImage({required this.url, this.crop});

  final String url;
  final Rect? crop;

  /// Bevorzugt die von uns gehostete Storage-Kopie (`storage_path`) statt
  /// `source_url` direkt zu zeigen (Bugfix: `source_url` ist bei manuellen
  /// Admin-Uploads nur ein Platzhalter wie "manual-upload:UUID", keine
  /// abrufbare URL — und auch bei recherchierten Bildern nur die externe
  /// Herkunfts-URL, die nicht dauerhaft/hotlink-fähig sein muss. Der echte
  /// Bild-Blob liegt immer im Storage-Bucket, sobald ensureCoverImage()
  /// erfolgreich war). `source_url` bleibt nur Fallback für Alt-Zeilen ohne
  /// storage_path.
  factory GalleryImage.fromRow(Map<String, dynamic> row) {
    final x = (row['crop_x'] as num?)?.toDouble();
    final y = (row['crop_y'] as num?)?.toDouble();
    final width = (row['crop_width'] as num?)?.toDouble();
    final height = (row['crop_height'] as num?)?.toDouble();
    final crop = (x != null && y != null && width != null && height != null)
        ? Rect.fromLTWH(x, y, width, height)
        : null;
    final storagePath = row['storage_path'] as String?;
    final url = storagePath != null
        ? Supabase.instance.client.storage
              .from(_kImagesBucket)
              .getPublicUrl(storagePath)
        : row['source_url'] as String;
    return GalleryImage(url: url, crop: crop);
  }
}

/// Stellt das separate Profilfoto vor die Bildergalerie, ohne ein identisches
/// Bild doppelt anzuzeigen. Für Personen und Ensembles ist `photo_url` die
/// verbindliche Miniaturansicht; `sort_order` ordnet nur die Galerie dahinter.
List<GalleryImage> profilePhotoFirst(
  String? profilePhotoUrl,
  List<GalleryImage> gallery,
) {
  if (profilePhotoUrl == null || profilePhotoUrl.isEmpty) return gallery;
  return [
    GalleryImage(url: profilePhotoUrl),
    ...gallery.where((image) => image.url != profilePhotoUrl),
  ];
}

/// Freigegebene Galerie-Bilder einer Person/eines Ensembles, in
/// redaktioneller Reihenfolge (niedrigster sort_order zuerst = Titelbild).
/// Leere Liste, wenn noch keine über die neue Admin-Galerie gepflegt wurden
/// — der Aufrufer fällt dann auf das bisherige Einzel-photo_url-Feld
/// zurück (siehe person_detail_screen.dart/ensemble_detail_screen.dart),
/// kein Verhalten bricht für noch nicht migrierte Entitäten.
final entityGalleryProvider = FutureProvider.autoDispose
    .family<List<GalleryImage>, ({String originType, String originId})>((
      ref,
      key,
    ) async {
      final rows = await Supabase.instance.client
          .from('images')
          .select(
            'source_url, storage_path, crop_x, crop_y, crop_width, crop_height',
          )
          .eq('origin_type', key.originType)
          .eq('origin_id', key.originId)
          .inFilter('license_status', ['confirmed_free', 'confirmed_licensed'])
          .order('sort_order', ascending: true);

      return (rows as List)
          .cast<Map<String, dynamic>>()
          .map(GalleryImage.fromRow)
          .toList();
    });
