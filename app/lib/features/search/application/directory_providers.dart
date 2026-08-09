import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Datenquellen für den Verzeichnis-Browser im Suchtab (Tab "Künstler" /
/// "Ensembles" / "Orte", sichtbar solange keine Sucheingabe erfolgt ist).
///
/// Die Tabellen sind klein (persons ~28, ensembles ~32, venues ~37 Zeilen),
/// daher genügt ein vollständiger, alphabetisch sortierter Read ohne
/// Pagination.
///
/// `ascending: true` ist hier Pflicht, nicht Kosmetik: anders als der
/// JS-Supabase-Client (dort ist `ascending` standardmäßig `true`) defaultet
/// `order()` im Dart-Client (`postgrest` Paket) auf `ascending: false` — ohne
/// explizites `true` kam die Liste Z-A statt A-Z zurück.

const _kImagesBucket = 'ingested-images';

/// Titelbild (niedrigster sort_order) je Entität aus der Admin-Galerie
/// (`images`-Tabelle), pro `origin_id`. Nutzerfeedback: Künstler-Miniaturbilder
/// fehlten in der Verzeichnisliste, obwohl auf der Detailseite ein Bild
/// sichtbar ist — Grund: Das Detailbild kommt dort primär aus der Galerie
/// (siehe entityGalleryProvider), nicht aus der oft leeren `photo_url`-Spalte
/// direkt auf persons/ensembles. Diese Map liefert denselben Titelbild-Fallback
/// für die Verzeichnisliste.
Future<Map<String, String>> _coverImagesByOriginId(String originType) async {
  final rows = await Supabase.instance.client
      .from('images')
      .select('origin_id, source_url, storage_path, sort_order')
      .eq('origin_type', originType)
      .inFilter('license_status', ['confirmed_free', 'confirmed_licensed'])
      .order('sort_order', ascending: true);

  final covers = <String, String>{};
  for (final row in (rows as List).cast<Map<String, dynamic>>()) {
    final originId = row['origin_id'] as String;
    if (covers.containsKey(originId)) {
      continue; // erste Zeile = niedrigster sort_order
    }
    final storagePath = row['storage_path'] as String?;
    covers[originId] = storagePath != null
        ? Supabase.instance.client.storage
              .from(_kImagesBucket)
              .getPublicUrl(storagePath)
        : row['source_url'] as String;
  }
  return covers;
}

/// Bevorzugt das Galerie-Titelbild vor der eigenen `photo_url`-Spalte,
/// sobald eines existiert (siehe Kommentar oben — meist die bessere/
/// geprüfte Aufnahme). Der redaktionelle Avatar-Ausschnitt
/// (avatar_crop_x/y/width/height) wurde im Admin gegen die ursprüngliche
/// `photo_url` gewählt — greift stattdessen das Galeriebild, gehört der
/// Ausschnitt zu einem ANDEREN Bild und wird deshalb bewusst verworfen
/// (sonst würde z.B. ein am Kopf zugeschnittener Ausschnitt plötzlich
/// einen Fuß zeigen).
List<Map<String, dynamic>> _applyCoverFallback(
  List<Map<String, dynamic>> rows,
  Map<String, String> covers,
) {
  return rows.map((r) {
    final coverUrl = covers[r['id']];
    if (coverUrl == null) return r;
    return {
      ...r,
      'photo_url': coverUrl,
      'avatar_crop_x': null,
      'avatar_crop_y': null,
      'avatar_crop_width': null,
      'avatar_crop_height': null,
    };
  }).toList();
}

/// Alle Personen alphabetisch nach Name.
final allPersonsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((
  ref,
) async {
  final rawRows = await Supabase.instance.client
      .from('persons')
      .select(
        'id, slug, full_name, roles, photo_url, avatar_crop_x, avatar_crop_y, avatar_crop_width, avatar_crop_height',
      )
      .order('full_name', ascending: true);
  final covers = await _coverImagesByOriginId('person');
  return _applyCoverFallback(
    (rawRows as List).cast<Map<String, dynamic>>(),
    covers,
  );
});

/// Alle Ensembles alphabetisch nach Name.
final allEnsemblesProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
      final rawRows = await Supabase.instance.client
          .from('ensembles')
          .select(
            'id, slug, name, type, photo_url, avatar_crop_x, avatar_crop_y, avatar_crop_width, avatar_crop_height',
          )
          .order('name', ascending: true);
      final covers = await _coverImagesByOriginId('ensemble');
      return _applyCoverFallback(
        (rawRows as List).cast<Map<String, dynamic>>(),
        covers,
      );
    });

/// Alle Orte alphabetisch nach Name.
final allVenuesProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
      final rows = await Supabase.instance.client
          .from('venues')
          .select('id, slug, name, address_city')
          .order('name', ascending: true);
      return (rows as List).cast<Map<String, dynamic>>();
    });
