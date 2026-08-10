import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/time/munich_time.dart';
import '../../../core/widgets/event_card.dart';
import '../../../core/widgets/favorite_button.dart';
import '../../../core/widgets/genre_artwork.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../home/application/home_providers.dart';
import '../application/calendar_providers.dart';
import 'widgets/calendar_sync_sheet.dart';

DateTime _dayKey(DateTime d) => DateTime(d.year, d.month, d.day);

enum _CalendarViewMode { month, week, agenda }

class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  DateTime _focusedDay = MunichTime.now();
  DateTime _selectedDay = MunichTime.now();
  _CalendarViewMode _mode = _CalendarViewMode.month;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final l10n = AppLocalizations.of(context)!;
    final monthKey = MonthKey(_focusedDay.year, _focusedDay.month);
    final monthAsync = ref.watch(monthEventsProvider(monthKey));
    final eventsByDay = <DateTime, List<HomeEventItem>>{
      ...monthAsync.valueOrNull ?? const {},
    };
    // Woche-Format zeigt table_calendar zufolge die Mon-So-Woche um
    // _focusedDay — die kann in den vorigen/nächsten Monat hineinragen,
    // dessen Events monthEventsProvider (nur _focusedDay's Monat) nicht
    // enthält. Fehlender Monat wird bei Bedarf zusätzlich geladen.
    if (_mode == _CalendarViewMode.week) {
      final weekStart = _focusedDay.subtract(
        Duration(days: _focusedDay.weekday - 1),
      );
      final weekEnd = weekStart.add(const Duration(days: 6));
      for (final edge in [weekStart, weekEnd]) {
        if (edge.month != _focusedDay.month || edge.year != _focusedDay.year) {
          final edgeAsync = ref.watch(
            monthEventsProvider(MonthKey(edge.year, edge.month)),
          );
          eventsByDay.addAll(edgeAsync.valueOrNull ?? const {});
        }
      }
    }
    final dayAgenda = eventsByDay[_dayKey(_selectedDay)] ?? const [];

    // Füllt den sonst leeren Platz unter einem dünn besetzten Tag mit einer
    // Vorschau der nächsten Termine — nur die bereits geladenen Tage
    // (aktueller Monat bzw. Woche), keine zusätzliche Datenabfrage.
    final weekPreview = <HomeEventItem>[];
    final upcomingDayKeys =
        eventsByDay.keys
            .where(
              (d) =>
                  !isSameDay(d, _selectedDay) &&
                  !d.isBefore(_dayKey(MunichTime.now())),
            )
            .toList()
          ..sort();
    for (final d in upcomingDayKeys) {
      weekPreview.addAll(eventsByDay[d]!);
      if (weekPreview.length >= 6) break;
    }

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.screenPaddingMobile,
              vertical: AppSpacing.md,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.calendarTitle,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.sync_rounded, color: colors.textSecondary),
                  tooltip: l10n.calendarSyncTooltip,
                  onPressed: () => showModalBottomSheet(
                    context: context,
                    builder: (_) => const CalendarSyncSheet(),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.screenPaddingMobile,
            ),
            child: _ViewModeSwitcher(
              mode: _mode,
              onChanged: (mode) => setState(() => _mode = mode),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          if (_mode != _CalendarViewMode.agenda) ...[
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.screenPaddingMobile,
              ),
              child: TableCalendar(
                locale: Localizations.localeOf(context).toString(),
                firstDay: MunichTime.now().subtract(const Duration(days: 365)),
                lastDay: MunichTime.now().add(const Duration(days: 365)),
                focusedDay: _focusedDay,
                calendarFormat: _mode == _CalendarViewMode.week
                    ? CalendarFormat.week
                    : CalendarFormat.month,
                selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
                eventLoader: (day) => eventsByDay[_dayKey(day)] ?? const [],
                onDaySelected: (selected, focused) => setState(() {
                  _selectedDay = selected;
                  _focusedDay = focused;
                }),
                onPageChanged: (focused) =>
                    setState(() => _focusedDay = focused),
                daysOfWeekHeight: 20,
                // table_calendar zeichnet für eventLoader-Tage sonst ZUSÄTZLICH
                // seine eigenen Standard-Marker (kleine Punkte in der
                // Paket-Standardfarbe) UNTER dem von _DayCell schon
                // gezeichneten Punkt-Indikator — zwei optisch unterschiedliche
                // Punkt-Systeme auf demselben Tag, verwirrend statt doppelt
                // informativ. markersMaxCount: 0 unterdrückt nur die
                // Paket-eigenen Marker, _DayCell's eigener Indikator bleibt.
                calendarStyle: const CalendarStyle(markersMaxCount: 0),
                headerStyle: HeaderStyle(
                  formatButtonVisible: false,
                  titleCentered: true,
                  titleTextStyle: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                  leftChevronIcon: Icon(
                    Icons.chevron_left_rounded,
                    color: colors.textSecondary,
                  ),
                  rightChevronIcon: Icon(
                    Icons.chevron_right_rounded,
                    color: colors.textSecondary,
                  ),
                ),
                daysOfWeekStyle: DaysOfWeekStyle(
                  weekdayStyle: TextStyle(
                    color: colors.textTertiary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                  weekendStyle: TextStyle(
                    color: colors.textTertiary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                calendarBuilders: CalendarBuilders(
                  defaultBuilder: (context, day, focusedDay) => _DayCell(
                    day: day,
                    colors: colors,
                    eventCount: (eventsByDay[_dayKey(day)] ?? const []).length,
                  ),
                  outsideBuilder: (context, day, focusedDay) =>
                      _DayCell(day: day, colors: colors, dimmed: true),
                  todayBuilder: (context, day, focusedDay) => _DayCell(
                    day: day,
                    colors: colors,
                    isToday: true,
                    eventCount: (eventsByDay[_dayKey(day)] ?? const []).length,
                  ),
                  selectedBuilder: (context, day, focusedDay) => _DayCell(
                    day: day,
                    colors: colors,
                    isToday: isSameDay(day, MunichTime.now()),
                    isSelected: true,
                    eventCount: (eventsByDay[_dayKey(day)] ?? const []).length,
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Divider(color: colors.separator, height: 1),
          ],
          Expanded(
            child: _mode == _CalendarViewMode.agenda
                ? const _FullAgendaList()
                : _DayAgendaList(
                    day: _selectedDay,
                    events: dayAgenda,
                    weekPreview: weekPreview.take(6).toList(),
                    isLoading: monthAsync.isLoading && !monthAsync.hasValue,
                    error: monthAsync.hasError ? monthAsync.error : null,
                  ),
          ),
        ],
      ),
    );
  }
}

List<({_CalendarViewMode mode, String label, IconData icon})> _viewModeOptions(
  AppLocalizations l10n,
) => [
  (
    mode: _CalendarViewMode.month,
    label: l10n.calendarViewMonth,
    icon: Icons.calendar_view_month_rounded,
  ),
  (
    mode: _CalendarViewMode.week,
    label: l10n.calendarViewWeek,
    icon: Icons.view_week_rounded,
  ),
  (
    mode: _CalendarViewMode.agenda,
    label: l10n.calendarViewAgenda,
    icon: Icons.view_agenda_rounded,
  ),
];

/// Eigene Pill-Segmentsteuerung statt Material [SegmentedButton] — dessen
/// Standarddarstellung zeigt für die aktive Option ein Checkmark-Icon neben
/// dem Label, was hier neben "Monat/Woche/Agenda" seltsam wirkte
/// (Nutzerfeedback: "Die Gruppierung... ist irgendwie komisch designt").
/// Stattdessen eine durchgehende Pille mit einem einzigen farbig gefüllten
/// Segment für die aktive Ansicht, wie iOS-Segmented-Controls.
class _ViewModeSwitcher extends StatelessWidget {
  const _ViewModeSwitcher({required this.mode, required this.onChanged});

  final _CalendarViewMode mode;
  final ValueChanged<_CalendarViewMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: colors.backgroundSecondary,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          for (final option in _viewModeOptions(AppLocalizations.of(context)!))
            Expanded(
              child: _ViewModeSegment(
                label: option.label,
                icon: option.icon,
                selected: option.mode == mode,
                onTap: () => onChanged(option.mode),
              ),
            ),
        ],
      ),
    );
  }
}

class _ViewModeSegment extends StatelessWidget {
  const _ViewModeSegment({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: selected ? colors.accentPrimary : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 15,
              color: selected ? Colors.white : colors.textSecondary,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DayAgendaList extends StatelessWidget {
  const _DayAgendaList({
    required this.day,
    required this.events,
    required this.weekPreview,
    required this.isLoading,
    required this.error,
  });

  final DateTime day;
  final List<HomeEventItem> events;
  final List<HomeEventItem> weekPreview;
  final bool isLoading;
  final Object? error;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final l10n = AppLocalizations.of(context)!;
    final dayLabel = DateFormat(
      'EEEE, d. MMMM',
      Localizations.localeOf(context).toString(),
    ).format(day);

    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (error != null) {
      return Center(
        child: Text(
          l10n.errorLoadingGeneric(error.toString()),
          style: TextStyle(color: colors.error),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.screenPaddingMobile,
        vertical: AppSpacing.md,
      ),
      children: [
        if (events.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
            child: Text(
              l10n.calendarNoEventsOnDay(dayLabel),
              style: TextStyle(color: colors.textSecondary),
            ),
          )
        else ...[
          // Nur ab zwei Terminen sinnvoll — "planen" bei nur einem Konzert
          // gibt es nichts zu koordinieren (Phase D.3, Nutzerwunsch Punkt
          // 12: "Sind Überschneidungen vorhanden? ... danach noch eine
          // passende Veranstaltung?").
          if (events.length > 1)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: OutlinedButton.icon(
                onPressed: () => context.push(
                  '/evening-plan?date=${day.toIso8601String().split('T').first}',
                ),
                icon: const Icon(Icons.event_note_rounded, size: 16),
                label: Text(l10n.calendarPlanEvening),
              ),
            ),
          for (var i = 0; i < events.length; i++) ...[
            if (i > 0) Divider(color: colors.separator, height: 1),
            _EventTile(event: events[i], colors: colors),
          ],
        ],
        if (weekPreview.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          Text(
            l10n.calendarMoreThisWeek,
            style: TextStyle(
              color: colors.textTertiary,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            height: 164,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: weekPreview.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(width: AppSpacing.cardGap),
              itemBuilder: (context, i) {
                final e = weekPreview[i];
                return EventCard(
                  eventId: e.id,
                  title: e.title,
                  venueAndTime: e.venueAndTime,
                  genre: e.genre,
                  imageUrl: e.imageUrl,
                  badgeLabel: e.badge,
                  onTap: () => context.push('/event/${e.slug}'),
                );
              },
            ),
          ),
        ],
      ],
    );
  }
}

/// Agenda-Modus: chronologische Liste ab heute mit Tages-Überschriften statt
/// der Tagesauswahl in Monat/Woche — siehe [agendaEventsProvider].
class _FullAgendaList extends ConsumerWidget {
  const _FullAgendaList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;
    final l10n = AppLocalizations.of(context)!;
    final async = ref.watch(agendaEventsProvider);

    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Text(
          l10n.errorLoadingGeneric(e.toString()),
          style: TextStyle(color: colors.error),
        ),
      ),
      data: (agenda) {
        final eventsByDay = agenda.byDay;
        if (eventsByDay.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Text(
                l10n.calendarNoEventsUpcoming,
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.textSecondary),
              ),
            ),
          );
        }

        final days = eventsByDay.keys.toList()..sort();
        // Bei Erreichen des Seiten-Limits (siehe agendaEventsProvider) gibt
        // es einen Hinweis statt die Liste kommentarlos abzuschneiden — echte
        // Pagination lohnt sich für Konzerttermine nicht, aber ein stiller
        // Cutoff wäre irreführend.
        final itemCount = days.length + (agenda.truncated ? 1 : 0);
        return ListView.builder(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.screenPaddingMobile,
            vertical: AppSpacing.md,
          ),
          itemCount: itemCount,
          itemBuilder: (context, i) {
            if (i >= days.length) {
              return Padding(
                padding: const EdgeInsets.only(top: AppSpacing.lg),
                child: Text(
                  l10n.calendarMoreEventsHint,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: colors.textTertiary, fontSize: 12.5),
                ),
              );
            }
            final day = days[i];
            final events = eventsByDay[day]!;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (i > 0) const SizedBox(height: AppSpacing.lg),
                Text(
                  DateFormat(
                    'EEEE, d. MMMM',
                    Localizations.localeOf(context).toString(),
                  ).format(day),
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                for (final event in events)
                  _EventTile(event: event, colors: colors),
              ],
            );
          },
        );
      },
    );
  }
}

class _EventTile extends StatelessWidget {
  const _EventTile({required this.event, required this.colors});

  final HomeEventItem event;
  final AppColorsExtension colors;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 4),
      leading: SizedBox(
        width: 56,
        height: 56,
        child: event.imageUrl != null
            ? ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: CachedNetworkImage(
                  imageUrl: event.imageUrl!,
                  fit: BoxFit.cover,
                  errorWidget: (context, url, error) => GenreArtwork(
                    genre: event.genre,
                    borderRadius: BorderRadius.circular(10),
                    showIcon: true,
                  ),
                  placeholder: (context, url) => GenreArtwork(
                    genre: event.genre,
                    borderRadius: BorderRadius.circular(10),
                    showIcon: true,
                  ),
                ),
              )
            : GenreArtwork(
                genre: event.genre,
                borderRadius: BorderRadius.circular(10),
                showIcon: true,
              ),
      ),
      title: Text(
        event.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: FontWeight.w700,
          color: colors.textPrimary,
        ),
      ),
      subtitle: Text(
        event.venueAndTime,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: colors.textSecondary, fontSize: 12.5),
      ),
      trailing: FavoriteButton(eventId: event.id, size: 20),
      onTap: () => context.push('/event/${event.slug}'),
    );
  }
}

/// Ein Kalendertag: Zahl plus bis zu zwei dezente Punkte darunter, wenn
/// Termine vorhanden sind — statt der vorherigen, kaum sichtbaren
/// table_calendar-Standardmarker. "Heute" ist die einzige voll gefüllte
/// Markierung, ein ausgewählter (aber nicht heutiger) Tag bekommt nur einen
/// Ring, damit beide Zustände nicht optisch verschmelzen.
class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.colors,
    this.isToday = false,
    this.isSelected = false,
    this.dimmed = false,
    this.eventCount = 0,
  });

  final DateTime day;
  final AppColorsExtension colors;
  final bool isToday;
  final bool isSelected;
  final bool dimmed;
  final int eventCount;

  @override
  Widget build(BuildContext context) {
    final textColor = dimmed
        ? colors.textTertiary.withValues(alpha: 0.5)
        : colors.textPrimary;

    Widget number = Text(
      '${day.day}',
      style: TextStyle(fontSize: 13, color: textColor),
    );

    if (isToday) {
      number = Container(
        width: 24,
        height: 24,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: colors.accentSecondary,
          shape: BoxShape.circle,
        ),
        child: Text(
          '${day.day}',
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            // Fest dunkel statt colors.backgroundPrimary, siehe Kommentar
            // zur Badge-Farbe in event_card.dart — gleicher Kontrastfehler
            // (2.15:1 im Light-Theme) auf demselben Goldton.
            color: Color(0xFF1C1C1E),
          ),
        ),
      );
    } else if (isSelected) {
      number = Container(
        width: 24,
        height: 24,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: colors.accentPrimary, width: 1.5),
        ),
        child: Text(
          '${day.day}',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
      );
    }

    final showDots = !dimmed && eventCount > 0;
    // Die Event-Punkte sind ein reines Farbsignal ohne Text-/Icon-Rückfall
    // (siehe Barrierefreiheits-Audit) — ein hint ergänzt die Ansage um die
    // Anzahl, ohne TableCalendars eigene Tag-Semantik zu überschreiben.
    return Semantics(
      hint: eventCount > 0
          ? (eventCount == 1
                ? '1 Veranstaltung'
                : '$eventCount Veranstaltungen')
          : null,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          number,
          const SizedBox(height: 3),
          SizedBox(
            height: 4,
            child: showDots
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < (eventCount > 1 ? 2 : 1); i++)
                        Container(
                          width: 4,
                          height: 4,
                          margin: EdgeInsets.only(left: i == 0 ? 0 : 3),
                          decoration: BoxDecoration(
                            color: colors.accentPrimary.withValues(alpha: 0.55),
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  )
                : null,
          ),
        ],
      ),
    );
  }
}
