import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../l10n/generated/app_localizations.dart';

/// Konzertplanung für einen Abend (Phase D.3, docs/09-feature-expansion-
/// plan.md, Nutzerwunsch Punkt 12) — bewusst OHNE Gastro-Empfehlungen oder
/// echte Reisezeiten (beides bräuchte eine externe API mit eigenem Zugang,
/// siehe Plan-Dokument). Was allein aus den vorhandenen Eventdaten geht:
/// alle Termine EINES Tages in einer Zeitleiste, Überschneidungen
/// erkennen, und pro Konzert zeigen, was DANACH am selben Abend noch geht.
class _EveningEvent {
  const _EveningEvent({
    required this.id,
    required this.slug,
    required this.title,
    required this.start,
    required this.durationMinutes,
    required this.venueName,
  });

  final String id;
  final String slug;
  final String title;
  final DateTime start;
  final int? durationMinutes;
  final String? venueName;

  DateTime get end => start.add(Duration(minutes: durationMinutes ?? 120));
}

final _eveningEventsProvider =
    FutureProvider.family<List<_EveningEvent>, DateTime>((ref, day) async {
      final dayStart = DateTime(day.year, day.month, day.day).toUtc();
      final dayEnd = dayStart.add(const Duration(days: 1));

      final rows = await Supabase.instance.client
          .from('events')
          .select(
            'id, slug, title, start_datetime, duration_minutes, venues(name)',
          )
          .eq('status', 'scheduled')
          .gte('start_datetime', dayStart.toIso8601String())
          .lt('start_datetime', dayEnd.toIso8601String())
          .order('start_datetime', ascending: true);

      return (rows as List)
          .map((r) {
            final start = DateTime.tryParse(r['start_datetime'] ?? '');
            if (start == null) return null;
            return _EveningEvent(
              id: r['id'] as String,
              slug: r['slug'] as String,
              title: r['title'] as String? ?? '',
              start: start.toLocal(),
              durationMinutes: r['duration_minutes'] as int?,
              venueName: r['venues']?['name'] as String?,
            );
          })
          .whereType<_EveningEvent>()
          .toList();
    });

class EveningPlanScreen extends ConsumerWidget {
  const EveningPlanScreen({required this.day, super.key});

  final DateTime day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_eveningEventsProvider(day));
    final colors = context.appColors;
    final l10n = AppLocalizations.of(context)!;
    final weekdayNames = [
      l10n.weekdayMonday,
      l10n.weekdayTuesday,
      l10n.weekdayWednesday,
      l10n.weekdayThursday,
      l10n.weekdayFriday,
      l10n.weekdaySaturday,
      l10n.weekdaySunday,
    ];
    final dateLabel =
        '${weekdayNames[day.weekday - 1]}, ${day.day}.${day.month}.${day.year}';

    return Scaffold(
      appBar: AppBar(title: Text(l10n.eveningPlanAppBarTitle(dateLabel))),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) =>
            Center(child: Text(l10n.errorLoadingGeneric(e.toString()))),
        data: (events) {
          if (events.isEmpty) {
            return Center(
              child: Text(
                l10n.eveningPlanNoEvents,
                style: TextStyle(color: colors.textSecondary),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(AppSpacing.screenPaddingMobile),
            itemCount: events.length,
            itemBuilder: (context, i) {
              final event = events[i];
              final overlaps = events.where((other) {
                if (other.id == event.id) return false;
                return event.start.isBefore(other.end) &&
                    other.start.isBefore(event.end);
              }).toList();
              // "Danach": beginnt nach Ende dieses Events, aber noch
              // innerhalb einer plausiblen Abend-Anschlussspanne (3h) —
              // sonst würde z.B. ein Konzert um 20 Uhr am nächsten Tag
              // fälschlich als "danach" erscheinen.
              final after = events.where((other) {
                if (other.id == event.id) return false;
                final gap = other.start.difference(event.end);
                return gap >= Duration.zero && gap <= const Duration(hours: 3);
              }).toList();

              return Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                child: Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: colors.backgroundSecondary,
                    borderRadius: BorderRadius.circular(AppSpacing.md),
                    border: overlaps.isNotEmpty
                        ? Border.all(color: colors.error, width: 1)
                        : Border.all(color: colors.separator),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            _time(event.start),
                            style: TextStyle(
                              color: colors.accentPrimary,
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: GestureDetector(
                              onTap: () => context.push('/event/${event.slug}'),
                              child: Text(
                                event.title,
                                style: TextStyle(
                                  color: colors.textPrimary,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        [
                          event.venueName,
                          event.durationMinutes != null
                              ? l10n.eveningPlanDurationUntil(
                                  event.durationMinutes!,
                                  _time(event.end),
                                )
                              : l10n.eveningPlanUntil(_time(event.end)),
                        ].whereType<String>().join(' · '),
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: 12.5,
                        ),
                      ),
                      if (overlaps.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.sm),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.warning_amber_rounded,
                              size: 15,
                              color: colors.error,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                l10n.eveningPlanOverlapsWith(
                                  overlaps.map((o) => o.title).join(', '),
                                ),
                                style: TextStyle(
                                  color: colors.error,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (after.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          l10n.eveningPlanAfter,
                          style: TextStyle(
                            color: colors.textTertiary,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        for (final a in after)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: GestureDetector(
                              onTap: () => context.push('/event/${a.slug}'),
                              child: Text(
                                '${_time(a.start)} · ${a.title}${a.venueName != null ? ' (${a.venueName})' : ''}',
                                style: TextStyle(
                                  color: colors.accentPrimary,
                                  fontSize: 12.5,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

String _time(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
