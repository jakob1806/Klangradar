import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Eine aktive Stadt-Region (regions.type = 'city', is_active = true) —
/// seit der Stadt-Erweiterung (Berlin/Hamburg/Frankfurt/Wien neben München,
/// siehe docs/12-city-expansion-import.md) gibt es davon mehr als eine.
class CityRegion {
  const CityRegion({required this.id, required this.name, required this.slug});

  final String id;
  final String name;
  final String slug;

  factory CityRegion.fromRow(Map<String, dynamic> row) => CityRegion(
    id: row['id'] as String,
    name: row['name'] as String,
    slug: row['slug'] as String,
  );
}

final activeCityRegionsProvider = FutureProvider.autoDispose<List<CityRegion>>((
  ref,
) async {
  final rows = await Supabase.instance.client
      .from('regions')
      .select('id, name, slug')
      .eq('type', 'city')
      .eq('is_active', true)
      .order('name');
  return (rows as List)
      .map((r) => CityRegion.fromRow(r as Map<String, dynamic>))
      .toList();
});

/// Ausgewählte Stadt (region_id), nach der Karte/Suche gefiltert werden --
/// `null` heißt "alle Städte" (bisheriges Verhalten vor der Stadt-
/// Erweiterung). Bewusst nur In-Memory-State (kein SharedPreferences-
/// Persistieren) für diesen ersten Wurf; die Auswahl setzt bei App-Neustart
/// wieder auf "alle" zurück.
final selectedCityRegionProvider = StateProvider<CityRegion?>((ref) => null);
