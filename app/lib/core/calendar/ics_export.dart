import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../utils/share_position.dart';

class IcsEventInput {
  const IcsEventInput({
    required this.uid,
    required this.title,
    required this.start,
    required this.end,
    this.description,
    this.location,
    this.url,
  });

  final String uid;
  final String title;
  final DateTime start;
  final DateTime end;
  final String? description;
  final String? location;
  final String? url;
}

/// Erzeugt eine .ics-Datei und öffnet das System-Teilen-Menü. iOS/Android
/// bieten für `text/calendar`-Dateien dort direkt „Zum Kalender hinzufügen"
/// an — kein eigener Kalender-Picker nötig (siehe
/// docs/05-navigation-structure.md, „Kalender synchronisieren"). Eine .ics
/// mit mehreren VEVENT-Blöcken importieren beide Systeme als Sammel-Import
/// ("Alle hinzufügen"), daher genügt [shareMultiple] auch für den
/// Sync-Sheet-Bulk-Export der Favoriten.
class IcsExport {
  const IcsExport._();

  static Future<void> shareEvent({
    required BuildContext context,
    required String uid,
    required String title,
    required DateTime start,
    String? description,
    DateTime? end,
    int? durationMinutes,
    String? location,
    String? url,
  }) async {
    final effectiveEnd =
        end ?? start.add(Duration(minutes: durationMinutes ?? 120));
    await shareMultiple(
      // ignore: use_build_context_synchronously
      context: context,
      events: [
        IcsEventInput(
          uid: uid,
          title: title,
          start: start,
          end: effectiveEnd,
          description: description,
          location: location,
          url: url,
        ),
      ],
      fileName: 'event_$uid.ics',
      subject: title,
    );
  }

  static Future<void> shareMultiple({
    required BuildContext context,
    required List<IcsEventInput> events,
    required String fileName,
    String? subject,
  }) async {
    final ics = _buildIcs(events);
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$fileName');
    await file.writeAsString(ics);

    if (!context.mounted) return;
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'text/calendar')],
      subject: subject,
      sharePositionOrigin: sharePositionOriginFor(context),
    );
  }

  static String _buildIcs(List<IcsEventInput> events) {
    final lines = [
      'BEGIN:VCALENDAR',
      'VERSION:2.0',
      'PRODID:-//Klassik München//DE',
    ];
    for (final e in events) {
      lines.addAll([
        'BEGIN:VEVENT',
        'UID:${e.uid}@klassikmuenchen.de',
        'DTSTAMP:${_formatUtc(DateTime.now())}',
        'DTSTART:${_formatUtc(e.start)}',
        'DTEND:${_formatUtc(e.end)}',
        'SUMMARY:${_escape(e.title)}',
        if (e.description != null && e.description!.isNotEmpty)
          'DESCRIPTION:${_escape(e.description!)}',
        if (e.location != null && e.location!.isNotEmpty)
          'LOCATION:${_escape(e.location!)}',
        if (e.url != null && e.url!.isNotEmpty) 'URL:${e.url}',
        'END:VEVENT',
      ]);
    }
    lines.add('END:VCALENDAR');
    return lines.join('\r\n');
  }

  static String _formatUtc(DateTime d) {
    final utc = d.toUtc();
    String pad2(int n) => n.toString().padLeft(2, '0');
    return '${utc.year}${pad2(utc.month)}${pad2(utc.day)}T${pad2(utc.hour)}${pad2(utc.minute)}${pad2(utc.second)}Z';
  }

  /// Escaping nach RFC 5545 §3.3.11 — Reihenfolge ist wichtig, Backslash zuerst.
  static String _escape(String s) => s
      .replaceAll('\\', '\\\\')
      .replaceAll(',', '\\,')
      .replaceAll(';', '\\;')
      .replaceAll('\n', '\\n');
}
