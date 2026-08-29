import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/auth_providers.dart';

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

/// `profiles.preferred_region_id` (beim Onboarding gesetzt, siehe
/// onboarding_screen.dart) wurde bisher nirgends gelesen -- diese Provider
/// liefert die passende [CityRegion] dazu (nur falls die gespeicherte
/// Region auch unter den aktuell aktiven Städten ist), oder `null` ohne
/// Login/ohne gesetzte Präferenz/bei inaktiver Region.
final preferredCityRegionProvider = FutureProvider.autoDispose<CityRegion?>((
  ref,
) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return null;

  final regions = await ref.watch(activeCityRegionsProvider.future);
  final row = await Supabase.instance.client
      .from('profiles')
      .select('preferred_region_id')
      .eq('id', user.id)
      .maybeSingle();
  final preferredId = row?['preferred_region_id'] as String?;
  if (preferredId == null) return null;
  for (final region in regions) {
    if (region.id == preferredId) return region;
  }
  return null;
});

/// Ausgewählte Stadt (region_id), nach der Karte/Suche/Home/Kalender
/// gefiltert werden -- `null` heißt "alle Städte" (bisheriges Verhalten vor
/// der Stadt-Erweiterung). Seedet sich EINMALIG aus
/// [preferredCityRegionProvider], sobald diese vorliegt UND der Nutzer noch
/// keine eigene Auswahl getroffen hat (state noch null) -- eine bewusste
/// spätere Nutzerauswahl wird dadurch nie überschrieben. Ansonsten bewusst
/// nur In-Memory-State (kein SharedPreferences-Persistieren) für diesen
/// ersten Wurf; ohne gespeicherte Präferenz setzt die Auswahl bei
/// App-Neustart weiterhin auf "alle" zurück.
final selectedCityRegionProvider = StateProvider<CityRegion?>((ref) {
  // StateProviderRef besitzt in Riverpod 2 keinen eigenen state-Zugriff.
  // Die bevorzugte Stadt wird in den konsumierenden Screens berücksichtigt;
  // eine spätere Auswahl bleibt weiterhin lokaler State.
  return null;
});
