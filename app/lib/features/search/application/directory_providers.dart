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

/// Nutzt das Galerie-Titelbild ausschließlich als Fallback. Ein vorhandenes
/// `photo_url` ist das verbindliche Profilfoto und muss in kleinen wie großen
/// Künstler-Miniaturen Vorrang behalten. Dadurch bleibt auch der zu diesem
/// Profilfoto gespeicherte Avatar-Ausschnitt gültig. Nur für Personen — bei
/// Ensembles/Venues gilt umgekehrt die Galerie als verbindlich, siehe
/// [applyDirectoryCoverGalleryFirst].
List<Map<String, dynamic>> applyDirectoryCoverFallback(
  List<Map<String, dynamic>> rows,
  Map<String, String> covers,
) {
  return rows.map((r) {
    final profilePhoto = r['photo_url'] as String?;
    if (profilePhoto != null && profilePhoto.isNotEmpty) return r;
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

/// Für Ensembles/Venues: das in der Admin-Galerie an Position 0 einsortierte
/// Bild (per Pfeil-Reihenfolge oder "Als Titelbild") ist verbindlich für
/// Miniaturansicht UND Detailansicht — anders als bei Personen hat ein
/// älteres, separates `photo_url`-Feld hier keinen Vorrang mehr, sonst
/// änderte "Als Titelbild" in der Galerie sichtbar nichts in der App.
List<Map<String, dynamic>> applyDirectoryCoverGalleryFirst(
  List<Map<String, dynamic>> rows,
  Map<String, String> covers,
) {
  return rows.map((r) {
    final coverUrl = covers[r['id']];
    final photoUrl = coverUrl ?? (r['photo_url'] as String?);
    if (photoUrl == (r['photo_url'] as String?)) return r;
    return {...r, 'photo_url': photoUrl};
  }).toList();
}

/// Alle Personen alphabetisch nach Name.
final allPersonsProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  final rawRows = await Supabase.instance.client
      .from('persons')
      .select(
        'id, slug, full_name, roles, photo_url, avatar_crop_x, avatar_crop_y, avatar_crop_width, avatar_crop_height',
      )
      .order('full_name', ascending: true);
  final covers = await _coverImagesByOriginId('person');
  return applyDirectoryCoverFallback(
    (rawRows as List).cast<Map<String, dynamic>>(),
    covers,
  );
});

/// Alle Ensembles alphabetisch nach Name.
final allEnsemblesProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  final rawRows = await Supabase.instance.client
      .from('ensembles')
      .select(
        'id, slug, name, type, photo_url, avatar_crop_x, avatar_crop_y, avatar_crop_width, avatar_crop_height',
      )
      .eq('is_resolution_placeholder', false)
      .eq('is_family_root', false)
      .order('name', ascending: true);
  final covers = await _coverImagesByOriginId('ensemble');
  return applyDirectoryCoverGalleryFirst(
    (rawRows as List).cast<Map<String, dynamic>>(),
    covers,
  );
});

/// Alle Orte alphabetisch nach Name.
final allVenuesProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  final rawRows = await Supabase.instance.client
      .from('venues')
      .select('id, slug, name, address_city, photo_url')
      .order('name', ascending: true);
  final covers = await _coverImagesByOriginId('venue');
  return applyDirectoryCoverGalleryFirst(
    (rawRows as List).cast<Map<String, dynamic>>(),
    covers,
  );
});
