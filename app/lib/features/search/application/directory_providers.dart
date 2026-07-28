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

/// Alle Personen alphabetisch nach Name.
final allPersonsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
      final rows = await Supabase.instance.client
          .from('persons')
          .select('id, slug, full_name, roles, photo_url')
          .order('full_name', ascending: true);
      return (rows as List).cast<Map<String, dynamic>>();
    });

/// Alle Ensembles alphabetisch nach Name.
final allEnsemblesProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
      final rows = await Supabase.instance.client
          .from('ensembles')
          .select('id, slug, name, type, photo_url')
          .order('name', ascending: true);
      return (rows as List).cast<Map<String, dynamic>>();
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
