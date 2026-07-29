import 'package:device_calendar/device_calendar.dart';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// Bottom-Sheet zur Auswahl EINES Gerätekalenders — Nutzeranfrage: "Kalender
/// Button soll die ICS-Datei nicht teilen, sondern automatisch importieren
/// (Auswahl der Kalenderkategorie beachten)". Zeigt nur beschreibbare
/// Kalender (z.B. "Privat"/"Arbeit"/ein Google-Konto), markiert den
/// Standardkalender des Geräts.
Future<Calendar?> showCalendarPickerSheet(
  BuildContext context,
  List<Calendar> calendars,
) {
  return showModalBottomSheet<Calendar>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _CalendarPickerSheet(calendars: calendars),
  );
}

class _CalendarPickerSheet extends StatelessWidget {
  const _CalendarPickerSheet({required this.calendars});

  final List<Calendar> calendars;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.6,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenPaddingMobile,
            AppSpacing.lg,
            AppSpacing.screenPaddingMobile,
            AppSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'In welchen Kalender?',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: AppSpacing.md),
              for (final calendar in calendars)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: calendar.color != null
                          ? Color(calendar.color!)
                          : colors.accentPrimary,
                      shape: BoxShape.circle,
                    ),
                  ),
                  title: Text(calendar.name ?? 'Unbenannter Kalender'),
                  subtitle: calendar.accountName != null
                      ? Text(
                          calendar.accountName!,
                          style: TextStyle(
                            color: colors.textSecondary,
                            fontSize: 12.5,
                          ),
                        )
                      : null,
                  trailing: calendar.isDefault == true
                      ? Text(
                          'Standard',
                          style: TextStyle(
                            color: colors.textTertiary,
                            fontSize: 11,
                          ),
                        )
                      : null,
                  onTap: () => Navigator.of(context).pop(calendar),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
