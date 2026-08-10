/// Phase C.2 (docs/09-feature-expansion-plan.md), Nutzerwunsch Punkt 4:
/// "Klavierkonzerte dieses Wochenende", "Mahler unter 50 Euro". Kein
/// KI-Aufruf — ein einfacher, deterministischer Muster-Abgleich für die
/// zwei häufigsten kombinierbaren Filter (Preis, Datum), die
/// search_all() nicht selbst versteht (das ist reine Textähnlichkeits-
/// suche). Der erkannte Teil wird aus dem Suchtext entfernt, damit
/// "unter 50 Euro" nicht selbst als (sinnloser) Textmatch-Begriff an
/// search_all geht.
library;

import '../../../core/time/munich_time.dart';

class ParsedSearchQuery {
  const ParsedSearchQuery({
    required this.coreQuery,
    this.maxPrice,
    this.dateFrom,
    this.dateTo,
    this.freeOnly = false,
  });

  final String coreQuery;
  final double? maxPrice;
  final DateTime? dateFrom;
  final DateTime? dateTo;
  final bool freeOnly;

  bool get hasFilters => maxPrice != null || dateFrom != null || freeOnly;
}

final _pricePattern = RegExp(
  r'(?:unter|bis(?:\s+zu)?|max(?:imal)?)\s+(\d+)\s*(?:€|euro)',
  caseSensitive: false,
);
final _freePattern = RegExp(r'\bkostenlos(e[nrs]?)?\b', caseSensitive: false);

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// (from, to, matchedPhrase) für die erste erkannte Datumsphrase, oder
/// null. `to` ist EXKLUSIV (für den Vergleich `start < to`).
({DateTime from, DateTime to, String phrase})? _matchDatePhrase(String q) {
  final now = MunichTime.now();
  final today = _dateOnly(now);

  bool contains(String phrase) => q.contains(phrase);

  if (contains('heute')) {
    return (
      from: today,
      to: today.add(const Duration(days: 1)),
      phrase: 'heute',
    );
  }
  if (contains('morgen')) {
    final d = today.add(const Duration(days: 1));
    return (from: d, to: d.add(const Duration(days: 1)), phrase: 'morgen');
  }
  if (contains('dieses wochenende') || contains('am wochenende')) {
    // Samstag..Sonntag der aktuellen Woche (oder, falls schon vorbei,
    // "diese Woche" degeneriert einfach zu einem bereits verstrichenen
    // Zeitraum — bewusst kein Sprung in die nächste Woche, "dieses
    // Wochenende" ist eindeutig auf die laufende Woche bezogen).
    final saturday = today.add(Duration(days: (6 - today.weekday) % 7));
    return (
      from: saturday,
      to: saturday.add(const Duration(days: 2)),
      phrase: contains('dieses wochenende')
          ? 'dieses wochenende'
          : 'am wochenende',
    );
  }
  if (contains('nächste woche') || contains('naechste woche')) {
    final nextMonday = today.add(Duration(days: 8 - today.weekday));
    return (
      from: nextMonday,
      to: nextMonday.add(const Duration(days: 7)),
      phrase: contains('nächste woche') ? 'nächste woche' : 'naechste woche',
    );
  }
  if (contains('diese woche')) {
    final monday = today.subtract(Duration(days: today.weekday - 1));
    return (
      from: today,
      to: monday.add(const Duration(days: 7)),
      phrase: 'diese woche',
    );
  }
  return null;
}

ParsedSearchQuery parseNaturalSearchQuery(String raw) {
  var remaining = raw.toLowerCase();
  double? maxPrice;
  DateTime? dateFrom;
  DateTime? dateTo;
  var freeOnly = false;

  final priceMatch = _pricePattern.firstMatch(remaining);
  if (priceMatch != null) {
    maxPrice = double.tryParse(priceMatch.group(1)!);
    remaining = remaining.replaceRange(priceMatch.start, priceMatch.end, ' ');
  }

  if (_freePattern.hasMatch(remaining)) {
    freeOnly = true;
    remaining = remaining.replaceAll(_freePattern, ' ');
  }

  final dateMatch = _matchDatePhrase(remaining);
  if (dateMatch != null) {
    dateFrom = dateMatch.from;
    dateTo = dateMatch.to;
    remaining = remaining.replaceAll(dateMatch.phrase, ' ');
  }

  final core = remaining.replaceAll(RegExp(r'\s+'), ' ').trim();

  return ParsedSearchQuery(
    coreQuery: core,
    maxPrice: maxPrice,
    dateFrom: dateFrom,
    dateTo: dateTo,
    freeOnly: freeOnly,
  );
}
