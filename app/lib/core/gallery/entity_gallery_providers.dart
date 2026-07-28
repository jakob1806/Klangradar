import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Ein Galerie-Bild mit optionalem redaktionellem Querformat-Zuschnitt
/// (siehe Admin-Crop-Tool). `crop` ist bereits in ein [Rect] umgewandelt
/// (Anteile 0..1), passend zu [CroppedNetworkImage].
class GalleryImage {
  const GalleryImage({required this.url, this.crop});

  final String url;
  final Rect? crop;

  factory GalleryImage.fromRow(Map<String, dynamic> row) {
    final x = (row['crop_x'] as num?)?.toDouble();
    final y = (row['crop_y'] as num?)?.toDouble();
    final width = (row['crop_width'] as num?)?.toDouble();
    final height = (row['crop_height'] as num?)?.toDouble();
    final crop = (x != null && y != null && width != null && height != null)
        ? Rect.fromLTWH(x, y, width, height)
        : null;
    return GalleryImage(url: row['source_url'] as String, crop: crop);
  }
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
          .select('source_url, crop_x, crop_y, crop_width, crop_height')
          .eq('origin_type', key.originType)
          .eq('origin_id', key.originId)
          .inFilter('license_status', ['confirmed_free', 'confirmed_licensed'])
          .order('sort_order', ascending: true);

      return (rows as List)
          .cast<Map<String, dynamic>>()
          .map(GalleryImage.fromRow)
          .toList();
    });
