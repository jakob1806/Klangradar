import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/role_labels.dart';
import '../../../core/gallery/entity_gallery_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/time/munich_time.dart';
import '../../../core/widgets/detail_card.dart';
import '../../../core/widgets/detail_hero_background.dart';
import '../../../core/widgets/entity_event_row.dart';
import '../../../core/widgets/entity_photo_gallery.dart';
import '../../../core/widgets/external_links_row.dart';
import '../../../core/widgets/genre_artwork.dart';
import '../../../core/widgets/past_events_expansion.dart';
import '../../../core/widgets/report_content_sheet.dart';
import '../../../core/widgets/similar_entities_row.dart';
import '../../../core/widgets/source_hint.dart';
import '../../../l10n/generated/app_localizations.dart';

final _personProvider = FutureProvider.family<Map<String, dynamic>?, String>((
  ref,
  slug,
) async {
  final client = Supabase.instance.client;
  final person = await client
      .from('persons')
      .select('*, member_of:ensembles!member_of_ensemble_id(slug, name)')
      .eq('slug', slug)
      .maybeSingle();
  if (person == null) return null;

  final events = await client
      .from('event_participants')
      .select('role, events(id, slug, title, start_datetime, venues(name))')
      .eq('person_id', person['id'])
      .order('events(start_datetime)', ascending: true);

  final provenance = await client
      .from('field_provenance')
      .select('field_name, source_name, source_url, retrieved_at, confidence')
      .eq('entity_type', 'person')
      .eq('entity_id', person['id']);

  // "Ähnliche Künstler" (Phase D.2, docs/09-feature-expansion-plan.md,
  // Nutzerwunsch Punkt 7) — bewusst einfache Heuristik statt eines eigenen
  // Empfehlungsdienstes: gleiche Rolle(n) UND (falls vorhanden) dasselbe
  // Instrument, nie sich selbst. Reicht für "andere Cellist:innen"/"andere
  // Dirigent:innen" ohne neue Infrastruktur.
  final roles = (person['roles'] as List?)?.cast<String>() ?? const [];
  List<dynamic> similar = const [];
  if (roles.isNotEmpty) {
    var query = client
        .from('persons')
        .select('slug, full_name, photo_url, roles, instrument')
        .overlaps('roles', roles)
        .neq('id', person['id']);
    if (person['instrument'] != null) {
      query = query.eq('instrument', person['instrument']);
    }
    similar = await query.limit(8);
    // Ohne Instrument-Treffer (oder gar kein Instrument gepflegt) bleibt
    // die reine Rollen-Überschneidung als Fallback bestehen — leere Liste
    // wäre für z.B. "Dirigent:in" schade, nur weil kein Instrument gesetzt
    // ist.
    if (similar.isEmpty && person['instrument'] != null) {
      similar = await client
          .from('persons')
          .select('slug, full_name, photo_url, roles, instrument')
          .overlaps('roles', roles)
          .neq('id', person['id'])
          .limit(8);
    }
  }

  return {
    'person': person,
    'events': events,
    'sources': fieldSourcesFromRows(provenance),
    'similar': similar,
  };
});

/// Volles Geburts-/Sterbedatum statt nur des Jahres (Nutzerfeedback) — DB
/// liefert birth_date/death_date als "YYYY-MM-DD"-Datumsstring.
String _formatDate(String isoDate) {
  final date = DateTime.tryParse(isoDate);
  if (date == null) return isoDate;
  return '${date.day}.${date.month}.${date.year}';
}

class PersonDetailScreen extends ConsumerWidget {
  const PersonDetailScreen({required this.slug, super.key});

  final String slug;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_personProvider(slug));
    final colors = context.appColors;
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) =>
            Center(child: Text(l10n.errorLoadingGeneric(e.toString()))),
        data: (data) {
          if (data == null) {
            return Center(child: Text(l10n.personNotFound));
          }
          final person = data['person'] as Map<String, dynamic>;
          final gallery = ref.watch(
            entityGalleryProvider((
              originType: 'person',
              originId: person['id'] as String,
            )),
          );
          final events = data['events'] as List;
          final sources = data['sources'] as Map<String, FieldSource>;
          final similar = data['similar'] as List;
          final roles = (person['roles'] as List?)?.cast<String>() ?? [];
          // Ein Komponist "kommt" nicht selbst zu einer Aufführung seines
          // Werks — er ist der "Programmgeber", kein Mitwirkender vor Ort
          // (Nutzerfeedback: "Komponisten sind ja nur der Programmgeber,
          // nicht der Mitwirkende"). Deshalb nach der ROLLE je Verknüpfung
          // trennen, nicht nach Lebensdatum: Verknüpfungen mit Rolle
          // "komponist" zeigen, wo ihre Werke aufgeführt werden (eigener
          // Abschnitt weiter unten), nur echte Auftritts-Rollen (Dirigent,
          // Solist, Chorleiter, Moderator) zählen als "Kommende/Vergangene
          // Veranstaltungen". Trifft auf verstorbene wie lebende Komponisten
          // gleichermaßen zu — ein lebender Komponist, der selbst dirigiert,
          // behält seine "Kommende Veranstaltungen" für genau diese Rolle.
          final performingRows = events
              .where((row) => row['role'] != 'komponist')
              .toList();
          final composerRows = events
              .where((row) => row['role'] == 'komponist')
              .toList();
          final hasPerformingRole =
              performingRows.isNotEmpty || roles.any((r) => r != 'komponist');
          final now = MunichTime.now();
          final upcoming = performingRows.where((row) {
            final start = MunichTime.tryParse(
              row['events']?['start_datetime'] ?? '',
            );
            return start != null && start.isAfter(now);
          }).toList();
          final past = performingRows
              .where((row) {
                final start = MunichTime.tryParse(
                  row['events']?['start_datetime'] ?? '',
                );
                return start != null && start.isBefore(now);
              })
              .toList()
              .reversed // jüngste zuerst statt älteste zuerst
              .take(20)
              .toList();
          final upcomingWorks = composerRows.where((row) {
            final start = MunichTime.tryParse(
              row['events']?['start_datetime'] ?? '',
            );
            return start != null && start.isAfter(now);
          }).toList();

          return CustomScrollView(
            slivers: [
              SliverAppBar(
                expandedHeight: 293,
                pinned: true,
                backgroundColor: colors.backgroundPrimary,
                iconTheme: const IconThemeData(color: Colors.white),
                flexibleSpace: FlexibleSpaceBar(
                  background: gallery.maybeWhen(
                    data: (images) {
                      final displayImages = profilePhotoFirst(
                        person['photo_url'] as String?,
                        images,
                      );
                      return displayImages.isNotEmpty
                          ? EntityPhotoGallery(
                              images: displayImages,
                              fallbackGenre: EventGenre.kammermusik,
                            )
                          : DetailHeroBackground(
                              photoUrl: person['photo_url'] as String?,
                              fallbackGenre: EventGenre.kammermusik,
                            );
                    },
                    orElse: () => DetailHeroBackground(
                      photoUrl: person['photo_url'] as String?,
                      fallbackGenre: EventGenre.kammermusik,
                    ),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screenPaddingMobile,
                  AppSpacing.lg,
                  AppSpacing.screenPaddingMobile,
                  AppSpacing.xxxl,
                ),
                sliver: SliverList.list(
                  children: [
                    Text(
                      person['full_name'] ?? '',
                      style: Theme.of(context).textTheme.headlineLarge,
                    ),
                    if (roles.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        children: roles
                            .map(
                              (r) => Chip(
                                label: Text(
                                  personRoleLabels(l10n)[r] ?? r,
                                  style: const TextStyle(fontSize: 11),
                                ),
                                visualDensity: VisualDensity.compact,
                              ),
                            )
                            .toList(),
                      ),
                    ],
                    if (person['nationality'] != null ||
                        person['instrument'] != null ||
                        person['birth_date'] != null) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        [
                          person['nationality'],
                          person['instrument'],
                          if (person['birth_date'] != null)
                            '* ${_formatDate(person['birth_date'] as String)}'
                                '${person['death_date'] != null ? ' † ${_formatDate(person['death_date'] as String)}' : ''}',
                        ].whereType<String>().join(' · '),
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                    if (person['member_of'] != null) ...[
                      const SizedBox(height: AppSpacing.xs),
                      GestureDetector(
                        onTap: () => context.push(
                          '/ensemble/${person['member_of']['slug']}',
                        ),
                        child: Text(
                          'Teil von ${person['member_of']['name']}',
                          style: TextStyle(
                            color: colors.accentPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                    if (person['biography_de'] != null) ...[
                      const SizedBox(height: AppSpacing.lg),
                      SectionHeaderWithSource(
                        title: l10n.personBiography,
                        colors: colors,
                        source: sources['biography_de'],
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        person['biography_de'],
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 14,
                          height: 1.5,
                        ),
                      ),
                    ],
                    if (person['current_roles_de'] != null) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              person['current_roles_de'],
                              style: TextStyle(
                                color: colors.textSecondary,
                                fontSize: 13,
                                height: 1.4,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          SourceHintIcon(source: sources['current_roles_de']),
                        ],
                      ),
                    ],
                    if (person['education_career_de'] != null) ...[
                      const SizedBox(height: AppSpacing.md),
                      SectionHeaderWithSource(
                        title: l10n.personEducationCareer,
                        colors: colors,
                        source: sources['education_career_de'],
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        person['education_career_de'],
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 13.5,
                          height: 1.5,
                        ),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.md),
                    ExternalLinksRow(
                      websiteUrl: person['website_url'] as String?,
                      wikipediaUrl: person['wikipedia_url'] as String?,
                      socialLinks:
                          person['social_links'] as Map<String, dynamic>?,
                    ),
                    _BioSection(
                      title: l10n.personRepertoireHighlights,
                      entries: person['repertoire_highlights'] as List?,
                      colors: colors,
                      source: sources['repertoire_highlights'],
                      lineOf: (e) => [
                        e['title'],
                        e['note'],
                      ].whereType<String>().join(' — '),
                    ),
                    _BioSection(
                      title: l10n.personAwards,
                      entries: person['awards'] as List?,
                      colors: colors,
                      source: sources['awards'],
                      lineOf: (e) => [
                        [
                          if (e['year'] != null) '${e['year']}',
                          e['title'],
                        ].whereType<String>().join(' · '),
                        e['note'],
                      ].whereType<String>().join(' — '),
                    ),
                    _BioSection(
                      title: l10n.personNotableRecordings,
                      entries: person['notable_recordings'] as List?,
                      colors: colors,
                      source: sources['notable_recordings'],
                      lineOf: (e) => [
                        e['title'],
                        e['label'],
                        if (e['year'] != null) '${e['year']}',
                      ].whereType<String>().join(' · '),
                      urlOf: (e) => e['url'] as String?,
                    ),
                    if (hasPerformingRole) ...[
                      const SizedBox(height: AppSpacing.xxl),
                      Text(
                        l10n.personUpcomingEvents,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      if (upcoming.isEmpty)
                        Text(
                          l10n.personNothingPlanned,
                          style: TextStyle(
                            color: colors.textTertiary,
                            fontSize: 13,
                          ),
                        )
                      else
                        DetailCard(
                          children: [
                            for (final row in upcoming)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.md,
                                ),
                                child: _EventRow(row: row, colors: colors),
                              ),
                          ],
                        ),
                    ],
                    if (past.isNotEmpty) ...[
                      SizedBox(
                        height: hasPerformingRole
                            ? AppSpacing.lg
                            : AppSpacing.xxl,
                      ),
                      PastEventsExpansion(
                        rows: [
                          for (final row in past)
                            _EventRow(row: row, colors: colors),
                        ],
                      ),
                    ],
                    // Eigener Abschnitt für Komponisten-Verknüpfungen — kein
                    // "kommt selbst", sondern "ihr Werk wird gespielt".
                    // Bewusst ohne "Aktuell nichts geplant"-Leerzustand
                    // (anders als oben): das ist hier nur eine Zusatzinfo,
                    // kein Kernversprechen des Profils.
                    if (upcomingWorks.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.xxl),
                      Text(
                        l10n.personWorksInProgram,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      DetailCard(
                        children: [
                          for (final row in upcomingWorks)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.md,
                              ),
                              child: _EventRow(row: row, colors: colors),
                            ),
                        ],
                      ),
                    ],
                    if (similar.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.xl),
                      Text(
                        l10n.personSimilarArtists,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      SimilarPersonsRow(entries: similar),
                    ],
                    const SizedBox(height: AppSpacing.lg),
                    ReportContentLink(
                      entityType: 'person',
                      entityId: person['id'] as String,
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Titelierter Abschnitt für strukturierte Bio-Listen (Repertoire,
/// Auszeichnungen, Aufnahmen) — rendert nichts, wenn der jsonb-Array leer
/// ist. `lineOf` formatiert einen Eintrag zu einer Zeile, `urlOf` macht die
/// Zeile optional antippbar (z.B. Link zur Aufnahme).
class _BioSection extends StatelessWidget {
  const _BioSection({
    required this.title,
    required this.entries,
    required this.colors,
    required this.lineOf,
    this.urlOf,
    this.source,
  });

  final String title;
  final List<dynamic>? entries;
  final AppColorsExtension colors;
  final String Function(Map<String, dynamic>) lineOf;
  final String? Function(Map<String, dynamic>)? urlOf;
  final FieldSource? source;

  @override
  Widget build(BuildContext context) {
    final items = (entries ?? const []).cast<Map<String, dynamic>>();
    if (items.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeaderWithSource(title: title, colors: colors, source: source),
          const SizedBox(height: AppSpacing.xs),
          for (final e in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: _BioEntryLine(
                text: lineOf(e),
                url: urlOf?.call(e),
                colors: colors,
              ),
            ),
        ],
      ),
    );
  }
}

class _BioEntryLine extends StatelessWidget {
  const _BioEntryLine({required this.text, required this.colors, this.url});

  final String text;
  final String? url;
  final AppColorsExtension colors;

  @override
  Widget build(BuildContext context) {
    final child = Text(
      '·  $text',
      style: TextStyle(
        color: url != null ? colors.accentPrimary : colors.textPrimary,
        fontSize: 13.5,
        height: 1.4,
      ),
    );
    if (url == null) return child;
    return GestureDetector(
      onTap: () =>
          launchUrl(Uri.parse(url!), mode: LaunchMode.externalApplication),
      child: child,
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({required this.row, required this.colors});
  final dynamic row;
  final AppColorsExtension colors;

  @override
  Widget build(BuildContext context) {
    final event = row['events'] as Map<String, dynamic>?;
    if (event == null) return const SizedBox.shrink();
    return EntityEventRow(
      title: event['title'] ?? '',
      slug: event['slug'] as String? ?? '',
      start: MunichTime.tryParse(event['start_datetime']),
      subtitle: event['venues']?['name'] as String?,
    );
  }
}
