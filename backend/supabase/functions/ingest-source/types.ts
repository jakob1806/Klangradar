// Gemeinsamer Vertrag zwischen den Connectoren (parsers/*.ts) und dem
// Orchestrator (index.ts) — jeder Connector normalisiert Quellformat-
// spezifische Daten (Schema.org/iCal/RSS) auf dieselbe Form, damit
// Matching/Dedupe/Write-Logik formatunabhängig bleiben.

export interface RawEvent {
  /** Stabile ID aus der Quelle, falls vorhanden (z.B. iCal UID) — noch
   * nicht für Matching genutzt, aber für spätere Idempotenz vorgesehen. */
  externalId: string | null;
  title: string;
  description: string | null;
  /** ISO 8601 */
  startDateTime: string;
  /** ISO 8601 — null wenn die Quelle keine Endzeit liefert. */
  endDateTime: string | null;
  /** Freitext-Venue-Name aus der Quelle, für find_matching_venue() wenn
   * die Source keine feste venue_id hat. */
  venueName: string | null;
  venueAddress: string | null;
  /** Raum/Buehne innerhalb der Venue, ohne eine eigene Venue anzulegen. */
  venueDetail?: string | null;
  url: string | null;
  imageUrl: string | null;
  priceMin: number | null;
  priceMax: number | null;
  isFree: boolean | null;
  /** Pflicht-Urheberrechtsvermerk von Quellen mit expliziter Lizenzauflage
   * (z.B. BayernCloud Tourismus: "Der entsprechende Urheberrechtsvermerk
   * der Datensätze muss mit angegeben werden"). Optional statt der
   * required-nullable Konvention der übrigen Felder — bewusste Ausnahme,
   * damit bestehende und parallel in Arbeit befindliche Connectoren diese
   * Felder nicht nachziehen müssen, nur weil das Interface um einen Fall
   * erweitert wurde, den nur eine einzelne Quelle betrifft. */
  attributionNotice?: string | null;
  attributionLicenseUrl?: string | null;
  /** Mitwirkende/Besetzung als Freitext-Namen, falls die Quelle/der Parser
   * das hergibt — zusätzliches Match-Signal für find_matching_event()
   * (siehe matching.ts), wirkt nur, sobald das kandidierende Event bereits
   * event_participants hat (z.B. durch enrich-event-references). Optional
   * wie attributionNotice, aus demselben Grund: kein bestehender Connector
   * muss das nachziehen, nur weil das Interface erweitert wurde. */
  castNames?: string[] | null;
}

export interface ParseResult {
  events: RawEvent[];
  /** Nicht-fatale Parse-Fehler pro Item — sammeln statt werfen, damit ein
   * kaputter Eintrag nicht den ganzen Lauf abbricht. */
  errors: string[];
}
