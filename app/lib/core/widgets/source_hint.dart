import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// Provenienz eines einzelnen, automatisiert recherchierten Feldes
/// (field_provenance-Zeile) — Grundlage für Phase 6's "dezente, aber
/// nachvollziehbare Quellenhinweise". Bislang nirgends in der App sichtbar,
/// obwohl seit Phase 1 pro Feld mitgeschrieben (_shared/provenance.ts).
class FieldSource {
  const FieldSource({
    required this.sourceName,
    this.sourceUrl,
    this.retrievedAt,
    this.confidence,
  });

  final String sourceName;
  final String? sourceUrl;
  final DateTime? retrievedAt;
  final String? confidence;

  factory FieldSource.fromRow(Map<String, dynamic> row) => FieldSource(
    sourceName: row['source_name'] as String? ?? 'Unbekannte Quelle',
    sourceUrl: row['source_url'] as String?,
    retrievedAt: DateTime.tryParse(row['retrieved_at'] as String? ?? ''),
    confidence: row['confidence'] as String?,
  );
}

/// field_name -> FieldSource, aus einem field_provenance-Query-Ergebnis für
/// EINE Entität gebaut (entity_type/entity_id werden vom Aufrufer bereits
/// gefiltert, hier nur noch nach field_name gruppiert).
Map<String, FieldSource> fieldSourcesFromRows(List<dynamic>? rows) {
  final map = <String, FieldSource>{};
  for (final row in rows ?? []) {
    final fieldName = row['field_name'] as String?;
    if (fieldName == null) continue;
    map[fieldName] = FieldSource.fromRow(row as Map<String, dynamic>);
  }
  return map;
}

const _confidenceLabel = {
  'confirmed': 'Bestätigt',
  'likely': 'Wahrscheinlich zutreffend',
  'uncertain': 'Unsicher',
};

/// Kleines, dezentes "ⓘ"-Icon neben einem automatisiert recherchierten
/// Textabschnitt — tippen öffnet ein Bottom-Sheet mit Quelle/Datum/
/// Vertrauensbewertung. Rendert nichts, wenn keine Provenienz vorliegt
/// (z. B. redaktionell gepflegte statt automatisiert recherchierte Felder).
class SourceHintIcon extends StatelessWidget {
  const SourceHintIcon({super.key, required this.source});

  final FieldSource? source;

  @override
  Widget build(BuildContext context) {
    final s = source;
    if (s == null) return const SizedBox.shrink();
    final colors = context.appColors;

    return GestureDetector(
      onTap: () => _showSourceSheet(context, s, colors),
      child: Padding(
        // Größeres Tap-Target (≥44×44pt laut docs/04-design-system.md
        // Abschnitt 7) als das sichtbare Icon selbst.
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Icon(
          Icons.info_outline_rounded,
          size: 14,
          color: colors.textTertiary,
        ),
      ),
    );
  }
}

void _showSourceSheet(
  BuildContext context,
  FieldSource s,
  AppColorsExtension colors,
) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Quelle', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            Text(
              s.sourceName,
              style: TextStyle(color: colors.textPrimary, fontSize: 14),
            ),
            if (s.sourceUrl != null) ...[
              const SizedBox(height: AppSpacing.xs),
              GestureDetector(
                onTap: () => launchUrl(
                  Uri.parse(s.sourceUrl!),
                  mode: LaunchMode.externalApplication,
                ),
                child: Text(
                  s.sourceUrl!,
                  style: TextStyle(color: colors.accentPrimary, fontSize: 13),
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: [
                if (s.retrievedAt != null)
                  _MetaChip(
                    label:
                        'Recherchiert am ${s.retrievedAt!.day.toString().padLeft(2, '0')}.'
                        '${s.retrievedAt!.month.toString().padLeft(2, '0')}.${s.retrievedAt!.year}',
                    colors: colors,
                  ),
                if (s.confidence != null)
                  _MetaChip(
                    label: _confidenceLabel[s.confidence] ?? s.confidence!,
                    colors: colors,
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Automatisiert recherchiert — bitte bei Zweifeln an der Quelle prüfen.',
              style: TextStyle(color: colors.textTertiary, fontSize: 11.5),
            ),
          ],
        ),
      ),
    ),
  );
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.label, required this.colors});
  final String label;
  final AppColorsExtension colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: colors.backgroundSecondary,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colors.separator),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11.5, color: colors.textSecondary),
      ),
    );
  }
}

/// Überschrift + optionalem SourceHintIcon in einer Zeile — Standardmuster
/// für Abschnitte mit automatisiert recherchiertem Inhalt (Geschichte,
/// Biografie, Instrumentierung, ...) über alle Detailseiten hinweg.
class SectionHeaderWithSource extends StatelessWidget {
  const SectionHeaderWithSource({
    super.key,
    required this.title,
    required this.colors,
    this.source,
  });

  final String title;
  final AppColorsExtension colors;
  final FieldSource? source;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleSmall),
        if (source != null) SourceHintIcon(source: source),
      ],
    );
  }
}
