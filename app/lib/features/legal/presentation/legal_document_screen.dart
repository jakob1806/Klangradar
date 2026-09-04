import 'package:flutter/material.dart';

/// Zeigt einen der Rechtstexte aus docs/legal/*.md an.
///
/// ENTWURF-Status: Die Inhalte sind Platzhalter, siehe docs/10-legal-status.md.
/// Sie sind hier als Dart-Strings eingebettet (statt als Asset geladen), um
/// keine zusätzliche Asset-Pipeline für drei kurze Texte einzuführen. Bei
/// künftigen inhaltlichen Änderungen: docs/legal/*.md UND diese Datei
/// synchron halten.
enum LegalDocument { privacyPolicy, terms, imprint }

class LegalDocumentScreen extends StatelessWidget {
  const LegalDocumentScreen({super.key, required this.document});

  final LegalDocument document;

  String get _title => switch (document) {
    LegalDocument.privacyPolicy => 'Datenschutzerklärung',
    LegalDocument.terms => 'AGB',
    LegalDocument.imprint => 'Impressum',
  };

  String get _body => switch (document) {
    LegalDocument.privacyPolicy => _privacyPolicyText,
    LegalDocument.terms => _termsText,
    LegalDocument.imprint => _imprintText,
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_title)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Entwurf — dieser Text wurde noch nicht anwaltlich geprüft '
                  'und enthält Platzhalter. Siehe docs/10-legal-status.md.',
                  style: TextStyle(fontSize: 12.5),
                ),
              ),
              const SizedBox(height: 16),
              SelectableText(
                _body,
                style: const TextStyle(fontSize: 13.5, height: 1.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

const _privacyPolicyText = '''
ENTWURF — nicht rechtsverbindlich. Vollständiger Text: docs/legal/datenschutzerklaerung.md

1. Verantwortlicher
Jakob Liess, Gabelsbergerstraße 6, 80333 München, jakob@klangradar.com (siehe Impressum).

2. Welche Daten wir verarbeiten
- E-Mail-Adresse, Passwort-Hash: Konto/Login (Art. 6 Abs. 1 lit. b DSGVO)
- Standortdaten (bei Erlaubnis): Kartenansicht, Umkreissuche (Einwilligung)
- Push-Token (Firebase Cloud Messaging): Benachrichtigungen (Einwilligung)
- Suchhistorie (eingeloggt): persönliche Suchhistorie, Empfehlungen
- Interessen/Präferenzen: personalisierte Empfehlungen
- Technische Nutzungsdaten (z. B. IP bei Requests): Betrieb, Sicherheit

3. Empfänger / Auftragsverarbeiter
- Supabase (Datenbank-, Auth- und Storage-Hosting)
- Google / Firebase Cloud Messaging (Push-Benachrichtigungen, ggf. USA-Transfer)
- Bei aktivierter Anmeldung mit Apple/Google: der jeweilige OAuth-Anbieter

4. Kartendarstellung
Nutzt OpenStreetMap-Kartenmaterial (flutter_map).

5. Betroffenenrechte
Auskunft, Berichtigung, Löschung, Einschränkung, Datenübertragbarkeit, Widerspruch
sowie Beschwerderecht bei einer Aufsichtsbehörde. Anfragen an: jakob@klangradar.com.

6. Widerruf
Standortfreigabe und Push-Benachrichtigungen jederzeit in den Geräte-/App-
Einstellungen widerrufbar.
''';

const _termsText = '''
ENTWURF — nicht rechtsverbindlich. Vollständiger Text: docs/legal/agb.md

1. Geltungsbereich
Diese AGB gelten für die Nutzung der App "Klangradar", angeboten von
Jakob Liess, Gabelsbergerstraße 6, 80333 München.

2. Leistungsbeschreibung
Die App aggregiert Informationen zu klassischen Konzerten, Chor-, Vokal-,
Kirchen- und Orchestermusik im Raum München.

3. Kein Vertragspartner für Ticketkäufe
Wir verkaufen selbst keine Tickets. Ein Kaufvertrag kommt ausschließlich
zwischen Nutzer:in und Veranstalter/Ticketanbieter zustande.

4. Registrierung
Für bestimmte Funktionen ist eine Registrierung per E-Mail erforderlich.

5. Haftungsausschluss für Veranstaltungsdaten
Termine, Preise und Ortsangaben können veraltet oder fehlerhaft sein. Maßgeblich
sind stets die Angaben des jeweiligen Veranstalters.

6. Datenquellen Dritter
Ein Teil der Veranstaltungsdaten wird automatisiert von Veranstalter-Websites
abgerufen (Details: docs/10-legal-status.md).

7. Haftung
Unbeschränkte Haftung für Vorsatz/grobe Fahrlässigkeit; im Übrigen begrenzt auf
den vertragstypischen, vorhersehbaren Schaden.

8. Kündigung
Konto jederzeit in den App-Einstellungen löschbar.
''';

const _imprintText = '''
ENTWURF — nicht rechtsverbindlich. Vollständiger Text: docs/legal/impressum.md

Angaben gemäß § 5 TMG/DDG:

Anbieter: Jakob Liess
Gabelsbergerstraße 6, 80333 München, Deutschland

Kontakt: jakob@klangradar.com
Vertretungsberechtigt: Jakob Liess

Verantwortlich für den Inhalt nach § 18 Abs. 2 MStV: Jakob Liess, Gabelsbergerstraße 6, 80333 München

Streitschlichtung: Online-Streitbeilegungsplattform der EU-Kommission:
https://ec.europa.eu/consumers/odr/
''';
