// Automatisches Fixen von Nutzer-Meldungen (content_reports) — Nutzerwunsch:
// "baue ein, dass von nutzer gemeldete fehler automatisch (und auf button
// befehl) gefixxt und behoben werden. dazu soll auch immer ein bericht
// erstellt werden." Aufrufbar sowohl per Cron (run_auto_fix_content_reports,
// siehe 20261006000009) als auch gezielt per Admin-Button (mit reportId).
//
// content_reports selbst ändert laut eigenem Seitenkommentar bewusst NIE
// automatisch Daten — das gilt weiterhin für den bisherigen redaktionellen
// "Erledigt"/"Verwerfen"-Fluss. Diese Function ist ein NEUER, separater,
// bewusst vorsichtig gehaltener automatischer Pfad, der IMMER einen
// content_report_fixes-Eintrag hinterlässt (der "Bericht") — auch wenn
// nichts geändert wurde, damit die Redaktion nachvollziehen kann, warum.
//
// Nutzerfeedback: "die nutzermeldungen sind mir nach wie vor nicht
// intelligent genug ... zu viele fälle landen auf 'manuell prüfen'. ich
// möchte da so wenig wie mgl. manuell machen." Deshalb bei fixViaSourceEvidence
// (der generische Pfad für alle Meldungsgründe außer wrong_image/
// wrong_artist/missing_program) drei Verschärfungen:
// a) Mehr erlaubte Felder pro Entitätstyp (siehe ALLOWED_FIELDS) — vorher
//    fielen z.B. Geburtsdatum/Nationalität/Instrument einer Person nie in
//    den automatischen Fix, selbst bei glasklarer Quellen-Evidenz.
// b) Mehrquellige Recherche (gatherCandidateSources): nicht mehr nur bei
//    fehlender URL eine Websuche versuchen, sondern IMMER zusätzlich zur
//    hinterlegten Quelle bis zu drei Websuche-Kandidaten vorbereiten und der
//    Reihe nach durchprobieren, bis eine Quelle eine belegte Korrektur
//    liefert.
// c) Selbstkritik-Runde: sind alle Quellen erschöpft, ohne dass die KI sich
//    sicher genug war, bekommt eine ZWEITE, unabhängige KI-Instanz die
//    bisherigen (zu vorsichtigen) Einschätzungen vorgelegt und prüft
//    kritisch, ob die Quelle die Angabe in Wahrheit doch eindeutig belegt.
//    Der scharfe Zitat-Grounding-Check (Punkt 2 unten) gilt dabei
//    unverändert — die Selbstkritik darf nur unnötige Vorsicht korrigieren,
//    nie das Beleg-Erfordernis aufweichen.
//
// Sicherheitsprinzipien:
// 1. Nur ein FESTES Set an Feldern pro Entitätstyp darf überhaupt
//    verändert werden (ALLOWED_FIELDS) — die KI kann nichts anderes
//    anfassen, egal was sie vorschlägt.
// 2. Jeder Vorschlag braucht ein wörtliches Zitat aus der tatsächlich
//    abgerufenen Quellseite (evidenceQuote) — kommt das Zitat im
//    abgerufenen Text nicht vor, wird der Vorschlag verworfen
//    (Grounding-Check gegen Halluzination).
// 3. Datumsvorschläge werden auf Plausibilität geprüft (max. 400 Tage
//    Abweichung vom bisherigen Wert) statt jedes KI-Datum blind zu
//    übernehmen.
// 4. wrong_artist korrigiert die role-Spalte bereits vorhandener
//    Mitwirkender IMMER (auch unbeaufsichtigt per Cron). Das ANLEGEN neuer
//    Mitwirkender/Personen sowie missing_program (Werk-/Programm-
//    Erkennung aus Freitext, legt bei Bedarf neue Werke/Komponisten an)
//    sind riskanter (Fuzzy-Matching/Neuanlage von Stammdaten) — diese
//    laufen NUR, wenn `adminInitiated` gesetzt ist, also ein Mensch gerade
//    explizit auf "Automatisch fixen" geklickt hat (siehe unten und
//    Nutzervorgabe: "ich möchte, dass alle nutzer meldungen, wenn vom
//    admin so veranlasst komplett gefixt werden. auch wenn es in deinen
//    augen risky ist"). Der unbeaufsichtigte Cron-Lauf (kein reportId,
//    kein adminInitiated-Flag) bleibt für genau diese beiden Fälle
//    weiterhin bei needs_manual_review — ein Mensch klickt dafür bewusst.
// 5. wrong_image nutzt die bereits bestehende, geprüfte Bilder-Pipeline
//    (research-entity-image) per internem HTTP-Aufruf wieder, statt eine
//    zweite Bildlogik zu bauen.
// 6. Neuangelegte Personen/Werke laufen über dasselbe Find-or-create-Muster
//    wie enrich-work-composer/enrich-event-references (exakter Namens-
//    abgleich, dann Fuzzy-Match über find_matching_person/find_matching_ensemble
//    mit demselben 0.85-Schwellwert, sonst Neuanlage mit is_verified=false)
//    — keine zweite, abweichende Matching-Logik.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { callAiFunction, hasAnyAiProviderConfigured, type AiFunctionDeclaration } from "../_shared/ai/router.ts";
import { isAllowedByRobots, USER_AGENT } from "../_shared/robots.ts";
import { isPublicImageUrl } from "../_shared/imageValidation.ts";
import { logSystemAction } from "../_shared/systemLog.ts";
import { searchDuckDuckGo } from "../_shared/duckDuckGoSearch.ts";
import { searchViaGeminiGrounding } from "../_shared/geminiGroundedSearch.ts";

type EntityType = "event" | "venue" | "person" | "ensemble";

const ENTITY_TABLE: Record<EntityType, string> = {
  event: "events",
  venue: "venues",
  person: "persons",
  ensemble: "ensembles",
};

// Schema-Feldname -> DB-Spalte, NUR für die hier gelisteten Typen/Felder
// überhaupt anwendbar — alles, was die KI sonst noch vorschlägt, wird
// stillschweigend ignoriert (siehe applyProposal()).
// Nutzerfeedback: "die nutzermeldungen sind mir nach wie vor nicht
// intelligent genug ... zu viele fälle landen auf 'manuell prüfen'" — ein
// Grund war, dass selbst bei eindeutiger Quellen-Evidenz viele Felder pro
// Entität gar nicht im automatischen Fix-Vokabular vorkamen (z.B. Geburts-/
// Sterbedatum einer Person). Jetzt deutlich breiter, bleibt aber pro
// Entitätstyp weiterhin ein FESTES Set (siehe Datei-Kommentar Punkt 1).
const ALLOWED_FIELDS: Record<EntityType, Record<string, string>> = {
  event: {
    title: "title",
    startDatetime: "start_datetime",
    status: "status",
    ticketUrl: "ticket_url",
    websiteUrl: "website_url",
  },
  venue: {
    title: "name",
    descriptionDe: "description_de",
    websiteUrl: "website_url",
    addressStreet: "address_street",
    addressZip: "address_zip",
    addressCity: "address_city",
    phone: "phone",
    publicTransport: "public_transport",
  },
  person: {
    title: "full_name",
    descriptionDe: "biography_de",
    websiteUrl: "website_url",
    nationality: "nationality",
    birthDate: "birth_date",
    deathDate: "death_date",
    instrument: "instrument",
  },
  ensemble: {
    title: "name",
    descriptionDe: "description_de",
    websiteUrl: "website_url",
    foundedYear: "founded_year",
    city: "city",
    country: "country",
  },
};

const DATE_ONLY_FIELDS = new Set(["birthDate", "deathDate"]);
const MIN_PLAUSIBLE_YEAR = 1200;

const EVENT_STATUS_VALUES = new Set(["scheduled", "cancelled", "postponed", "sold_out"]);
const MAX_DATE_DRIFT_DAYS = 400;
const PAGE_FETCH_TIMEOUT_MS = 12_000;
const MAX_PAGE_TEXT_CHARS = 6_000;

interface ContentReportRow {
  id: string;
  entity_type: EntityType;
  entity_id: string;
  reason: string;
  message: string | null;
}

interface FixResult {
  status: "fixed" | "needs_manual_review" | "error" | "code_bug_suspected";
  diagnosis: string;
  actionTaken?: string;
  fieldsChanged?: { table: string; id: string; field: string; before: unknown; after: unknown }[];
  aiProvider?: string;
  /** Nur bei status="code_bug_suspected" gefüllt — landet in code_fix_tasks
   * (siehe Migration 20261011000007), damit Claude Code die Aufgabe beim
   * nächsten Mal direkt aufgreifen kann, ohne dass ein Mensch sie erst
   * abtippen muss. */
  codeFixTask?: { title: string; prompt: string };
}

async function fetchPageText(url: string): Promise<string | null> {
  if (!isPublicImageUrl(url)) return null;
  if (!(await isAllowedByRobots(url))) return null;

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), PAGE_FETCH_TIMEOUT_MS);
  try {
    const res = await fetch(url, { headers: { "User-Agent": USER_AGENT }, signal: controller.signal });
    if (!res.ok) return null;
    const contentType = (res.headers.get("content-type") ?? "").toLowerCase();
    if (!contentType.includes("text/html") && !contentType.includes("application/xhtml")) return null;
    const html = await res.text();
    const text = html
      .replace(/<script[\s\S]*?<\/script>/gi, " ")
      .replace(/<style[\s\S]*?<\/style>/gi, " ")
      .replace(/<[^>]+>/g, " ")
      .replace(/\s+/g, " ")
      .trim();
    return text.slice(0, MAX_PAGE_TEXT_CHARS) || null;
  } catch {
    return null;
  } finally {
    clearTimeout(timeout);
  }
}

const FIX_PROPOSAL_FUNCTION: AiFunctionDeclaration = {
  name: "propose_content_fix",
  description:
    "Prüft eine Nutzer-Meldung zu einem Datenproblem gegen den Text der echten, tatsächlich abgerufenen Quellseite " +
    "und schlägt NUR bei eindeutiger, wörtlich belegbarer Textevidenz eine konkrete Korrektur vor.",
  parameters: {
    type: "object",
    properties: {
      confident: {
        type: "boolean",
        description:
          "true NUR, wenn die Quellseite eindeutig eine andere Angabe zeigt als aktuell gespeichert, UND du ein " +
          "wörtliches Zitat als Beleg liefern kannst. Bei jedem Zweifel: false.",
      },
      reasoning: {
        type: "string",
        description: "Kurze Begründung auf Deutsch: was war falsch, was ist laut Quelle richtig, oder warum unklar.",
      },
      evidenceQuote: {
        type: "string",
        description:
          "Pflicht wenn confident=true: ein wörtliches, kurzes (max. ~200 Zeichen) Zitat AUS DEM GELIEFERTEN " +
          "SEITENTEXT, das die Korrektur belegt. Nichts umformulieren oder erfinden.",
      },
      title: { type: "string", description: "Korrigierter Titel/Name, nur wenn abweichend und belegt." },
      descriptionDe: { type: "string", description: "Korrigierte Beschreibung/Biografie, nur wenn abweichend und belegt." },
      startDatetime: {
        type: "string",
        description: "Korrigiertes Datum/Uhrzeit als ISO-8601 (z.B. 2026-05-30T18:00:00), nur bei Events, nur wenn abweichend und belegt.",
      },
      status: {
        type: "string",
        description: "Korrigierter Status: scheduled, cancelled, postponed oder sold_out — nur bei Events, nur wenn abweichend und belegt.",
      },
      ticketUrl: { type: "string", description: "Korrigierter Ticket-Link, nur bei Events." },
      websiteUrl: { type: "string", description: "Korrigierter Website-Link." },
      nationality: { type: "string", description: "Korrigierte Nationalität, nur bei Personen." },
      birthDate: { type: "string", description: "Korrigiertes Geburtsdatum als YYYY-MM-DD, nur bei Personen." },
      deathDate: { type: "string", description: "Korrigiertes Sterbedatum als YYYY-MM-DD, nur bei Personen." },
      instrument: { type: "string", description: "Korrigiertes Hauptinstrument, nur bei Personen." },
      foundedYear: { type: "number", description: "Korrigiertes Gründungsjahr, nur bei Ensembles." },
      city: { type: "string", description: "Korrigierte Herkunfts-/Sitzstadt, nur bei Ensembles." },
      country: { type: "string", description: "Korrigiertes Herkunftsland, nur bei Ensembles." },
      addressStreet: { type: "string", description: "Korrigierte Straße samt Hausnummer, nur bei Venues." },
      addressZip: { type: "string", description: "Korrigierte Postleitzahl, nur bei Venues." },
      addressCity: { type: "string", description: "Korrigierte Stadt der Adresse, nur bei Venues." },
      phone: { type: "string", description: "Korrigierte Telefonnummer, nur bei Venues." },
      publicTransport: { type: "string", description: "Korrigierte ÖPNV-Anbindung, nur bei Venues." },
    },
    required: ["confident", "reasoning"],
  },
};

function isValidHttpUrl(value: string): boolean {
  try {
    const url = new URL(value);
    return url.protocol === "http:" || url.protocol === "https:";
  } catch {
    return false;
  }
}

const PARTICIPANT_ROLE_VALUES = new Set(["komponist", "dirigent", "solist", "chorleiter", "moderator"]);

const PARTICIPANT_ROLE_FUNCTION: AiFunctionDeclaration = {
  name: "propose_participant_role_fix",
  description:
    "Prüft eine Nutzer-Meldung zur Mitwirkenden-Zuordnung einer Veranstaltung. Meistens geht es um die Rolle " +
    "EINES bereits gelisteten Mitwirkenden — manchmal fehlt aber auch eine ganz neue Person (z.B. 'Dirigent XY " +
    "fehlt komplett'), das ist separat als newParticipant* markiert. Rollen gelten nur für Personen, nicht für " +
    "Ensembles.",
  parameters: {
    type: "object",
    properties: {
      confident: {
        type: "boolean",
        description:
          "true NUR, wenn aus Veranstaltungstitel/-beschreibung oder Meldungstext eindeutig hervorgeht, was zu " +
          "korrigieren ist (Rolle einer gelisteten Person ODER eine fehlende Person). Bei jedem Zweifel: false.",
      },
      reasoning: { type: "string", description: "Kurze Begründung auf Deutsch." },
      participantId: {
        type: "string",
        description: "Die exakte id des betroffenen Mitwirkenden aus der gelieferten Liste, falls dessen Rolle korrigiert werden soll.",
      },
      correctedRole: {
        type: "string",
        description: "Korrigierte/neue Rolle: komponist, dirigent, solist, chorleiter oder moderator.",
      },
      newParticipantName: {
        type: "string",
        description:
          "NUR füllen, wenn eine Person eindeutig als Mitwirkende:r fehlt (nicht schon in der Liste steht) UND " +
          "das aus Titel/Beschreibung/Meldung klar hervorgeht — voller Name.",
      },
    },
    required: ["confident", "reasoning"],
  },
};

interface ParticipantInfo {
  id: string;
  name: string;
  isPerson: boolean;
  currentRole: string | null;
}

const FUZZY_AUTO_THRESHOLD = 0.85;

/** Find-or-create für Personen — exakt dasselbe Muster wie
 * enrich-work-composer.ts (exakter ilike-Namensabgleich, dann
 * find_matching_person mit demselben 0.85-Schwellwert, sonst Neuanlage mit
 * is_verified=false) statt einer zweiten, abweichenden Matching-Logik.
 * Nur für adminInitiated-Pfade genutzt (Neuanlage von Stammdaten ist
 * riskanter als ein reines Feld-Update, siehe Datei-Kommentar). */
async function getOrCreatePersonSimple(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  name: string,
  context: Record<string, unknown>,
): Promise<{ id: string; created: boolean } | null> {
  const trimmed = name.trim();
  if (!trimmed) return null;

  const { data: existing } = await supabase.from("persons").select("id").ilike("full_name", trimmed).maybeSingle();
  if (existing) return { id: existing.id, created: false };

  const { data: fuzzyMatches } = await supabase.rpc("find_matching_person", { p_name: trimmed });
  const bestMatch = fuzzyMatches?.[0] as { id: string; full_name: string; similarity: number } | undefined;
  if (bestMatch && bestMatch.similarity >= FUZZY_AUTO_THRESHOLD) {
    await logSystemAction(supabase, "person", bestMatch.id, "fuzzy_auto_link", {
      matched_name: trimmed,
      linked_to: bestMatch.full_name,
      similarity: bestMatch.similarity,
      source: "auto-fix-content-report",
      ...context,
    });
    return { id: bestMatch.id, created: false };
  }

  const slug = await generateUniqueSlug(supabase, "persons", "slug", trimmed);
  const { data: created, error } = await supabase
    .from("persons")
    .insert({ full_name: trimmed, slug, is_verified: false, roles: [] })
    .select("id")
    .single();
  if (error || !created) return null;
  await logSystemAction(supabase, "person", created.id, "ai_auto_created", {
    name: trimmed,
    source: "auto-fix-content-report",
    ...context,
  }, "system (AI-Entscheidung, admin-veranlasst)");
  return { id: created.id, created: true };
}

/** Dupliziert aus enrich-work-composer.ts (kein gemeinsamer Modul-Raum
 * zwischen Edge Functions, siehe dortiger Kommentar) — generisch über
 * Tabelle/Spalte statt nur für persons, wird hier auch für works gebraucht. */
async function generateUniqueSlug(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  table: string,
  column: string,
  name: string,
): Promise<string> {
  const umlauts: Record<string, string> = { ä: "ae", ö: "oe", ü: "ue", ß: "ss", Ä: "ae", Ö: "oe", Ü: "ue" };
  let s = name;
  for (const [from, to] of Object.entries(umlauts)) s = s.split(from).join(to);
  const base = s
    .toLowerCase()
    .normalize("NFKD")
    .replace(/[̀-ͯ]/g, "")
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 80)
    .replace(/-+$/g, "") || "eintrag";

  for (let attempt = 0; attempt < 20; attempt++) {
    const candidate = attempt === 0 ? base : `${base}-${attempt + 1}`;
    const { data } = await supabase.from(table).select(column).eq(column, candidate).maybeSingle();
    if (!data) return candidate;
  }
  return `${base}-${crypto.randomUUID().slice(0, 8)}`;
}

/** Testfall aus echtem Nutzerreport: "Vladimir Jurowski besitzt keine
 * Kategorie" — bei genauerem Hinsehen role=null bei einem längst
 * korrekt verknüpften Mitwirkenden, kein Zuordnungsfehler. Braucht keine
 * externe Quelle (anders als fixViaSourceEvidence) — die Evidenz ist der
 * Veranstaltungstitel/-beschreibung selbst, üblicherweise eindeutig genug
 * ("Solist:in, Orchester, Dirigent:in" ist die gängige Titel-Konvention
 * für Konzertankündigungen). Sicherheit kommt stattdessen daraus, dass
 * participantId serverseitig gegen die tatsächlich geladene Liste geprüft
 * wird — die KI kann keine Person erfinden, die nicht schon als
 * Mitwirkende:r verknüpft ist. */
async function fixWrongArtist(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  report: ContentReportRow,
  adminInitiated: boolean,
): Promise<FixResult> {
  if (report.entity_type !== "event") {
    return {
      status: "needs_manual_review",
      diagnosis: "Falsche Künstler-/Werkzuordnung außerhalb einer Veranstaltung wird nicht automatisch geprüft.",
    };
  }

  const { data: event } = await supabase
    .from("events")
    .select("id, title, description_de")
    .eq("id", report.entity_id)
    .maybeSingle();
  if (!event) return { status: "error", diagnosis: "Veranstaltung nicht gefunden." };

  const { data: rawParticipants } = await supabase
    .from("event_participants")
    .select("id, role, persons(full_name), ensembles(name)")
    .eq("event_id", report.entity_id);

  type RawParticipant = { id: string; role: string | null; persons: { full_name: string } | null; ensembles: { name: string } | null };
  const participants: ParticipantInfo[] = ((rawParticipants ?? []) as RawParticipant[])
    .map((p) => ({
      id: p.id,
      name: p.persons?.full_name ?? p.ensembles?.name ?? "",
      isPerson: !!p.persons,
      currentRole: p.role,
    }))
    .filter((p) => p.name);

  if (participants.length === 0) {
    return { status: "needs_manual_review", diagnosis: "Keine Mitwirkenden hinterlegt, gegen die die Meldung geprüft werden könnte." };
  }

  if (!hasAnyAiProviderConfigured()) {
    return { status: "needs_manual_review", diagnosis: "Kein AI-Provider-Secret konfiguriert." };
  }

  const response = await callAiFunction(
    "Du bist Teil einer redaktionellen Datenpflege für eine Klassik-Konzert-App in München. Du prüfst eine " +
      "Nutzer-Meldung ('Künstler-/Werkzuordnung stimmt nicht') gegen Titel/Beschreibung einer Veranstaltung " +
      "und die bereits verknüpften Mitwirkenden." +
      (adminInitiated
        ? " Wenn eine Person eindeutig fehlt, darfst du sie über newParticipantName+correctedRole vorschlagen."
        : " Du darfst NUR die Rolle EINES bereits gelisteten Mitwirkenden korrigieren, niemals neue Personen vorschlagen.") +
      " Sei konservativ: bei jedem Zweifel confident=false.",
    `Meldungstext: ${report.message ?? "(kein Kommentar)"}\n\n` +
      `Veranstaltungstitel: ${event.title}\nBeschreibung: ${event.description_de ?? "(keine)"}\n\n` +
      `Bereits verknüpfte Mitwirkende:\n${
        participants.map((p) => `- id=${p.id}, name="${p.name}", typ=${p.isPerson ? "Person" : "Ensemble"}, aktuelle Rolle=${p.currentRole ?? "(keine)"}`).join("\n")
      }`,
    PARTICIPANT_ROLE_FUNCTION,
  );

  if (!response) return { status: "needs_manual_review", diagnosis: "KI-Aufruf fehlgeschlagen (alle Provider)." };
  const { args, provider } = response;

  if (args.confident !== true) {
    return {
      status: "needs_manual_review",
      diagnosis: typeof args.reasoning === "string" ? args.reasoning : "KI war sich nicht sicher genug.",
      aiProvider: provider,
    };
  }

  const correctedRole = typeof args.correctedRole === "string" ? args.correctedRole : "";
  const newName = typeof args.newParticipantName === "string" ? args.newParticipantName.trim() : "";

  // Fall A: eine bereits verknüpfte Person bekommt/ändert ihre Rolle.
  if (args.participantId) {
    const target = participants.find((p) => p.id === args.participantId);
    if (!target || !target.isPerson || !PARTICIPANT_ROLE_VALUES.has(correctedRole) || correctedRole === target.currentRole) {
      return {
        status: "needs_manual_review",
        diagnosis: `KI-Vorschlag bestand die Validierung nicht (unbekannte/ungültige Mitwirkenden-id, Ensemble statt ` +
          `Person, ungültige Rolle, oder keine echte Änderung). Begründung: ${args.reasoning ?? "-"}`,
        aiProvider: provider,
      };
    }

    const { error: updateError } = await supabase.from("event_participants").update({ role: correctedRole }).eq("id", target.id);
    if (updateError) {
      return { status: "error", diagnosis: `Update fehlgeschlagen: ${updateError.message}`, aiProvider: provider };
    }

    return {
      status: "fixed",
      diagnosis: `${args.reasoning ?? ""} („${target.name}“ ist ${
        target.currentRole ? `als „${target.currentRole}“` : "ohne Rolle"
      } verknüpft, korrekt ist „${correctedRole}“.)`,
      actionTaken: `Rolle von „${target.name}“: „${target.currentRole ?? "–"}“ → „${correctedRole}“`,
      fieldsChanged: [{ table: "event_participants", id: target.id, field: "role", before: target.currentRole, after: correctedRole }],
      aiProvider: provider,
    };
  }

  // Fall B: eine ganz neue Person fehlt als Mitwirkende:r — NUR admin-veranlasst
  // (Neuanlage/Fuzzy-Verknüpfung von Stammdaten, siehe Datei-Kommentar).
  if (adminInitiated && newName && PARTICIPANT_ROLE_VALUES.has(correctedRole)) {
    const person = await getOrCreatePersonSimple(supabase, newName, { event_id: report.entity_id, report_id: report.id });
    if (!person) {
      return {
        status: "needs_manual_review",
        diagnosis: `KI schlug „${newName}“ als fehlende:n Mitwirkende:n vor, Anlegen/Verknüpfen ist aber fehlgeschlagen.`,
        aiProvider: provider,
      };
    }
    const { data: inserted, error: insertError } = await supabase
      .from("event_participants")
      .insert({ event_id: report.entity_id, person_id: person.id, role: correctedRole, display_order: participants.length })
      .select("id")
      .single();
    if (insertError || !inserted) {
      return {
        status: "error",
        diagnosis: `Mitwirkende:n-Eintrag anlegen fehlgeschlagen: ${insertError?.message ?? "kein Ergebnis"}`,
        aiProvider: provider,
      };
    }
    return {
      status: "fixed",
      diagnosis: `${args.reasoning ?? ""} („${newName}“ fehlte komplett als Mitwirkende:r.)`,
      actionTaken: `Neu hinzugefügt: „${newName}“ als „${correctedRole}“${person.created ? " (neu angelegt)" : " (bestehende Person verknüpft)"}.`,
      fieldsChanged: [{ table: "event_participants", id: inserted.id, field: "added", before: null, after: `${newName} (${correctedRole})` }],
      aiProvider: provider,
    };
  }

  return {
    status: "needs_manual_review",
    diagnosis: adminInitiated
      ? `KI-Vorschlag unvollständig/ungültig. Begründung: ${args.reasoning ?? "-"}`
      : `KI schlug eine noch nicht verknüpfte Person vor („${newName || "?"}“) — das Anlegen neuer Mitwirkender läuft ` +
        `nur bei einem gezielten Klick auf "Automatisch fixen", nicht automatisch per Cron.`,
    aiProvider: provider,
  };
}

async function fixWrongImage(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  supabaseUrl: string,
  anonKey: string,
  entityType: EntityType,
  entityId: string,
): Promise<FixResult> {
  // Schritt 1: das aktuell gezeigte Bild als abgelehnt markieren — verhindert
  // laut imagePipeline.ts-Dedupe auch, dass genau dieses Bild bei der
  // gleich folgenden Suche unbemerkt wieder vorgeschlagen wird.
  await supabase
    .from("images")
    .update({ review_status: "rejected" })
    .eq("origin_type", entityType)
    .eq("origin_id", entityId)
    .eq("review_status", "approved");

  const headers = {
    "Content-Type": "application/json",
    apikey: anonKey,
    Authorization: `Bearer ${anonKey}`,
  };

  let searchRes: Response;
  try {
    searchRes = await fetch(`${supabaseUrl}/functions/v1/research-entity-image`, {
      method: "POST",
      headers,
      body: JSON.stringify({ entityType, entityId, mode: "search" }),
    });
  } catch (err) {
    return {
      status: "error",
      diagnosis: `Bildsuche nicht erreichbar: ${err instanceof Error ? err.message : String(err)}`,
    };
  }
  // deno-lint-ignore no-explicit-any
  const searchResult: any = await searchRes.json().catch(() => null);
  if (!searchResult?.found || !searchResult.imageUrl) {
    return {
      status: "needs_manual_review",
      diagnosis: `Bisheriges Bild als abgelehnt markiert, aber keine automatische Ersatzsuche erfolgreich: ${
        searchResult?.error ?? "kein Ergebnis"
      }`,
      actionTaken: "Bisheriges Bild abgelehnt (review_status=rejected).",
    };
  }

  let commitRes: Response;
  try {
    commitRes = await fetch(`${supabaseUrl}/functions/v1/research-entity-image`, {
      method: "POST",
      headers,
      body: JSON.stringify({
        entityType,
        entityId,
        mode: "commit",
        sourceUrl: searchResult.imageUrl,
        sourcePageUrl: searchResult.sourcePageUrl,
        sourceName: searchResult.sourceName,
        matchReason: `Automatischer Fix nach Nutzer-Meldung „falsches Bild“ — ${searchResult.matchReason ?? ""}`,
        licenseStatus: searchResult.suggestedLicenseStatus ?? "confirmed_licensed",
      }),
    });
  } catch (err) {
    return {
      status: "error",
      diagnosis: `Neues Bild gefunden, Übernahme aber fehlgeschlagen: ${err instanceof Error ? err.message : String(err)}`,
      actionTaken: "Bisheriges Bild abgelehnt (review_status=rejected).",
    };
  }
  // deno-lint-ignore no-explicit-any
  const commitResult: any = await commitRes.json().catch(() => null);
  if (!commitResult?.committed) {
    return {
      status: "needs_manual_review",
      diagnosis: `Neues Bild gefunden (${searchResult.sourceName ?? searchResult.imageUrl}), Übernahme aber fehlgeschlagen: ${
        commitResult?.error ?? "unbekannter Fehler"
      }`,
      actionTaken: "Bisheriges Bild abgelehnt (review_status=rejected).",
    };
  }

  return {
    status: "fixed",
    diagnosis: `Neues Bild automatisch übernommen — Quelle: ${searchResult.sourceName ?? "unbekannt"}${
      searchResult.matchReason ? ` (${searchResult.matchReason})` : ""
    }.`,
    actionTaken: "Altes Bild abgelehnt, neues Bild recherchiert und übernommen.",
    fieldsChanged: [
      { table: "images", id: commitResult.imageId, field: "primary_image", before: null, after: searchResult.imageUrl },
    ],
  };
}

/** Baut aus einem KI-Vorschlag die tatsächlichen DB-Updates (mit Validierung/
 * Plausibilitätsgrenzen je Feldtyp) — extrahiert aus fixViaSourceEvidence,
 * damit derselbe Code für jeden Quellenversuch UND die Selbstkritik-Runde
 * (siehe unten) gilt, statt Logik zu duplizieren. */
function buildUpdatesFromProposal(
  // deno-lint-ignore no-explicit-any
  args: Record<string, any>,
  // deno-lint-ignore no-explicit-any
  entity: Record<string, any>,
  table: string,
  allowed: Record<string, string>,
  entityId: string,
): { updates: Record<string, unknown>; fieldsChanged: { table: string; id: string; field: string; before: unknown; after: unknown }[] } {
  const fieldsChanged: { table: string; id: string; field: string; before: unknown; after: unknown }[] = [];
  const updates: Record<string, unknown> = {};

  for (const [schemaField, column] of Object.entries(allowed)) {
    const proposed = args[schemaField];
    if (proposed === undefined || proposed === null) continue;
    const before = entity[column];
    if (String(proposed).trim() === String(before ?? "").trim()) continue; // kein echter Unterschied

    if (schemaField === "startDatetime") {
      const parsed = new Date(proposed as string);
      if (Number.isNaN(parsed.getTime())) continue;
      if (before) {
        const driftDays = Math.abs(parsed.getTime() - new Date(before as string).getTime()) / 86_400_000;
        if (driftDays > MAX_DATE_DRIFT_DAYS) continue; // Plausibilitätsgrenze, siehe Datei-Kommentar
      }
      updates[column] = parsed.toISOString();
      fieldsChanged.push({ table, id: entityId, field: column, before, after: parsed.toISOString() });
      continue;
    }
    if (schemaField === "status") {
      if (!EVENT_STATUS_VALUES.has(String(proposed))) continue;
      updates[column] = proposed;
      fieldsChanged.push({ table, id: entityId, field: column, before, after: proposed });
      continue;
    }
    if (schemaField === "ticketUrl" || schemaField === "websiteUrl") {
      if (!isValidHttpUrl(String(proposed))) continue;
      updates[column] = proposed;
      fieldsChanged.push({ table, id: entityId, field: column, before, after: proposed });
      continue;
    }
    if (DATE_ONLY_FIELDS.has(schemaField)) {
      const parsed = new Date(String(proposed));
      if (Number.isNaN(parsed.getTime())) continue;
      const year = parsed.getUTCFullYear();
      if (year < MIN_PLAUSIBLE_YEAR || year > new Date().getUTCFullYear()) continue; // Plausibilitätsgrenze
      const dateOnly = parsed.toISOString().slice(0, 10);
      updates[column] = dateOnly;
      fieldsChanged.push({ table, id: entityId, field: column, before, after: dateOnly });
      continue;
    }
    if (schemaField === "foundedYear") {
      const year = Number(proposed);
      if (!Number.isInteger(year) || year < MIN_PLAUSIBLE_YEAR || year > new Date().getUTCFullYear()) continue;
      updates[column] = year;
      fieldsChanged.push({ table, id: entityId, field: column, before, after: year });
      continue;
    }
    // title / descriptionDe / restliche Textfelder (Nationalität, Instrument,
    // Adresse, Telefon, ÖPNV, ...): reine Textfelder, nur eine grobe Längenprüfung.
    const text = String(proposed).trim();
    if (text.length === 0 || text.length > 3000) continue;
    updates[column] = text;
    fieldsChanged.push({ table, id: entityId, field: column, before, after: text });
  }

  return { updates, fieldsChanged };
}

interface SourceCandidate {
  url: string;
  text: string;
  viaSearch: boolean;
}

/** Sammelt bis zu vier mögliche Quellseiten in Prioritätsreihenfolge: erst
 * die hinterlegte Ticket-/Website-URL, danach — Nutzerfeedback: "zu viele
 * fälle landen auf 'manuell prüfen'" — IMMER zusätzlich eine echte Websuche
 * (nicht mehr nur, wenn gar keine URL hinterlegt ist), falls die hinterlegte
 * Seite fehlt/nicht abrufbar ist ODER die KI dort später nicht sicher genug
 * war. Dieselben zwei bereits erprobten, kontingentschonenden Quellen wie
 * bei der Bilder-Recherche: DuckDuckGo zuerst ohne Key, Gemini-Grounding nur
 * als Ergänzung mit eigenem Kontingent. */
async function gatherCandidateSources(
  report: ContentReportRow,
  // deno-lint-ignore no-explicit-any
  entity: Record<string, any>,
  allowed: Record<string, string>,
): Promise<SourceCandidate[]> {
  const candidates: SourceCandidate[] = [];
  const primaryUrl = report.entity_type === "event"
    ? (entity.ticket_url as string | null) ?? (entity.website_url as string | null)
    : (entity.website_url as string | null);

  if (primaryUrl) {
    const text = await fetchPageText(primaryUrl);
    if (text) candidates.push({ url: primaryUrl, text, viaSearch: false });
  }

  const entityName = String(entity[allowed.title] ?? "").trim();
  if (entityName) {
    const query = report.entity_type === "event"
      ? `${entityName} München Termine Tickets`
      : `${entityName} München offizielle Website`;

    const urls: string[] = [];
    const ddgResults = await searchDuckDuckGo(query, 3);
    for (const r of ddgResults ?? []) urls.push(r.url);

    const geminiApiKey = Deno.env.get("GEMINI_SEARCH_API_KEY");
    if (geminiApiKey && urls.length < 3) {
      const groundedResults = await searchViaGeminiGrounding(geminiApiKey, query);
      for (const r of groundedResults ?? []) urls.push(r.url);
    }

    for (const url of urls.slice(0, 3)) {
      if (candidates.some((c) => c.url === url)) continue;
      const text = await fetchPageText(url);
      if (text) candidates.push({ url, text, viaSearch: true });
      if (candidates.length >= 4) break;
    }
  }

  return candidates;
}

async function fixViaSourceEvidence(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  report: ContentReportRow,
): Promise<FixResult> {
  const table = ENTITY_TABLE[report.entity_type];
  const allowed = ALLOWED_FIELDS[report.entity_type];
  const columns = ["id", ...new Set(Object.values(allowed))].join(", ");

  const { data: entity, error: loadError } = await supabase.from(table).select(columns).eq("id", report.entity_id).maybeSingle();
  if (loadError || !entity) {
    return { status: "error", diagnosis: `Entität nicht ladbar: ${loadError?.message ?? "nicht gefunden"}` };
  }

  if (!hasAnyAiProviderConfigured()) {
    return { status: "needs_manual_review", diagnosis: "Kein AI-Provider-Secret konfiguriert." };
  }

  const currentValues = Object.fromEntries(Object.entries(allowed).map(([schemaField, column]) => [schemaField, entity[column]]));
  const sources = await gatherCandidateSources(report, entity, allowed);

  if (sources.length === 0) {
    return {
      status: "needs_manual_review",
      diagnosis: "Weder eine hinterlegte Quell-URL noch eine Websuche lieferten eine abrufbare Seite mit Inhalt.",
    };
  }

  const attempts: { url: string; viaSearch: boolean; reasoning: string; provider: string }[] = [];
  let lastText = sources[sources.length - 1].text;
  let lastUrl = sources[sources.length - 1].url;

  // Schritt 1: jede Quelle der Reihe nach probieren, bis eine konkrete,
  // belegte Korrektur zustande kommt.
  for (const source of sources) {
    const response = await callAiFunction(
      "Du bist Teil einer redaktionellen Datenpflege für eine Klassik-Konzert-App in München. Du prüfst eine " +
        "Nutzer-Meldung ('etwas an diesem Eintrag stimmt nicht') gegen den echten, gerade abgerufenen Text der " +
        "offiziellen Quellseite. Sei SEHR konservativ: schlage nur etwas vor, wenn die Seite die Angabe eindeutig " +
        "und wörtlich belegt. Erfinde niemals Werte. Bei jedem Zweifel confident=false.",
      `Meldungsgrund: ${report.reason}\nNutzer-Kommentar: ${report.message ?? "(kein Kommentar)"}\n\n` +
        `Aktuell gespeicherte Werte: ${JSON.stringify(currentValues)}\n\n` +
        `Text der Quellseite (${source.url}):\n${source.text}`,
      FIX_PROPOSAL_FUNCTION,
    );
    if (!response) continue;
    const { args, provider } = response;
    lastText = source.text;
    lastUrl = source.url;

    if (args.confident !== true) {
      attempts.push({ url: source.url, viaSearch: source.viaSearch, reasoning: String(args.reasoning ?? "-"), provider });
      continue;
    }

    const quote = typeof args.evidenceQuote === "string" ? args.evidenceQuote.trim() : "";
    if (!quote || !source.text.toLowerCase().includes(quote.toLowerCase())) {
      attempts.push({
        url: source.url,
        viaSearch: source.viaSearch,
        reasoning: `Zitat nicht im Seitentext auffindbar (Grounding fehlgeschlagen). ${args.reasoning ?? ""}`,
        provider,
      });
      continue;
    }

    const { updates, fieldsChanged } = buildUpdatesFromProposal(args, entity, table, allowed, report.entity_id);
    if (fieldsChanged.length === 0) {
      attempts.push({
        url: source.url,
        viaSearch: source.viaSearch,
        reasoning: `Sicher (Zitat: „${quote}“), aber kein Wert bestand die Validierung oder wich nicht vom ` +
          `gespeicherten Wert ab. ${args.reasoning ?? ""}`,
        provider,
      });
      continue;
    }

    const { error: updateError } = await supabase.from(table).update(updates).eq("id", report.entity_id);
    if (updateError) return { status: "error", diagnosis: `Update fehlgeschlagen: ${updateError.message}`, aiProvider: provider };

    return {
      status: "fixed",
      diagnosis: `${args.reasoning ?? ""} (Beleg: „${quote}“, Quelle: ${source.url}${source.viaSearch ? ", per Websuche gefunden" : ""})`,
      actionTaken: fieldsChanged.map((f) => `${f.field}: „${f.before ?? "–"}“ → „${f.after}“`).join("; "),
      fieldsChanged,
      aiProvider: provider,
    };
  }

  // Schritt 2 — Selbstkritik-Runde (Nutzerfeedback: "zu viele fälle landen
  // auf 'manuell prüfen'"): statt nach der ersten Unsicherheit sofort
  // aufzugeben, bekommt eine ZWEITE, unabhängige KI-Instanz explizit die
  // bisherige(n) konservative(n) Einschätzung(en) vorgelegt und wird
  // gebeten, kritisch zu prüfen, ob dort zu vorsichtig geurteilt wurde. Der
  // Zitat-Grounding-Check bleibt exakt derselbe scharfe Filter wie oben —
  // die Selbstkritik-Runde darf NIE ein Zitat akzeptieren, das nicht
  // wörtlich im Seitentext steht, sie darf nur eine vorschnelle
  // confident=false-Einschätzung revidieren.
  if (attempts.length > 0) {
    const critique = await callAiFunction(
      "Du bist die zweite, unabhängige Prüfinstanz in einer redaktionellen Datenpflege für eine Klassik-Konzert-App " +
        "in München (Vier-Augen-Prinzip unter KIs). Eine erste KI-Instanz hat eine Nutzer-Meldung gegen eine " +
        "Quellseite geprüft und sich NICHT sicher genug für eine Korrektur gefühlt. Prüfe kritisch und unabhängig, " +
        "ob diese Einschätzung tatsächlich zutrifft, oder ob die Seite die Angabe in Wahrheit eindeutig und " +
        "wörtlich belegt. Sei dabei weiterhin sehr sorgfältig: erfinde niemals Werte, und liefere nur dann " +
        "confident=true, wenn du selbst ein wörtliches Zitat aus dem Text nennen kannst. Bei echtem Zweifel bleibt " +
        "es bei confident=false — es geht darum, unnötige Vorsicht zu korrigieren, nicht darum, das Risiko zu " +
        "erhöhen.",
      `Meldungsgrund: ${report.reason}\nNutzer-Kommentar: ${report.message ?? "(kein Kommentar)"}\n\n` +
        `Aktuell gespeicherte Werte: ${JSON.stringify(currentValues)}\n\n` +
        `Bisherige Einschätzung(en) der ersten KI-Instanz:\n${
          attempts.map((a) => `- Quelle ${a.url}: „${a.reasoning}“`).join("\n")
        }\n\n` +
        `Text der zuletzt geprüften Quellseite (${lastUrl}):\n${lastText}`,
      FIX_PROPOSAL_FUNCTION,
    );

    if (critique) {
      const { args, provider } = critique;
      if (args.confident === true) {
        const quote = typeof args.evidenceQuote === "string" ? args.evidenceQuote.trim() : "";
        if (quote && lastText.toLowerCase().includes(quote.toLowerCase())) {
          const { updates, fieldsChanged } = buildUpdatesFromProposal(args, entity, table, allowed, report.entity_id);
          if (fieldsChanged.length > 0) {
            const { error: updateError } = await supabase.from(table).update(updates).eq("id", report.entity_id);
            if (updateError) return { status: "error", diagnosis: `Update fehlgeschlagen: ${updateError.message}`, aiProvider: provider };
            return {
              status: "fixed",
              diagnosis: `Selbstkritik-Runde korrigierte eine zu vorsichtige erste Einschätzung: ${args.reasoning ?? ""} ` +
                `(Beleg: „${quote}“, Quelle: ${lastUrl})`,
              actionTaken: fieldsChanged.map((f) => `${f.field}: „${f.before ?? "–"}“ → „${f.after}“`).join("; "),
              fieldsChanged,
              aiProvider: provider,
            };
          }
        }
      }
    }
  }

  const sourceSummary = sources.map((s) => `${s.url}${s.viaSearch ? " (Websuche)" : ""}`).join("; ");
  const reasoningSummary = attempts.map((a) => a.reasoning).filter(Boolean).join(" | ") || "Keine KI-Antwort erhalten.";
  return {
    status: "needs_manual_review",
    diagnosis: `Geprüfte Quelle(n): ${sourceSummary}. Auch die Selbstkritik-Runde fand keine belegbare Korrektur. ${reasoningSummary}`,
  };
}

const WORK_LIST_FUNCTION: AiFunctionDeclaration = {
  name: "propose_program_works",
  description:
    "Extrahiert die im Programm einer Veranstaltung aufgeführten Werke samt Komponist:in aus Titel/Beschreibung " +
    "bzw. dem Text der Quellseite.",
  parameters: {
    type: "object",
    properties: {
      confident: {
        type: "boolean",
        description: "true NUR, wenn mindestens ein Werk mit eindeutigem Titel im Text genannt wird. Erfinde nichts.",
      },
      reasoning: { type: "string", description: "Kurze Begründung auf Deutsch." },
      works: {
        type: "array",
        description: "Gefundene Werke in Aufführungsreihenfolge, falls erkennbar.",
        items: {
          type: "object",
          properties: {
            title: { type: "string", description: "Werktitel, so wie in der Quelle genannt." },
            composerFullName: { type: "string", description: "Vollständiger Name der Komponist:in, falls im Text genannt." },
          },
          required: ["title"],
        },
      },
    },
    required: ["confident", "reasoning"],
  },
};

function normalizeWorkTitleSimple(title: string): string {
  return title
    .toLowerCase()
    .normalize("NFKD")
    .replace(/[̀-ͯ]/g, "")
    .replace(/[^a-z0-9 ]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

/** Live beobachtet: dieselbe Quellseite nennt ein Werk oft ZWEIMAL in
 * unterschiedlicher Ausführlichkeit — einmal kurz in einer Übersicht
 * ("March of the Resistance"), einmal vollständig im formalen Programm
 * ("March of the Resistance aus Star Wars: Das Erwachen der Macht") — die
 * KI extrahiert beides als zwei separate works-Einträge IN DERSELBEN
 * Antwort. Ein reiner Exakt-Titel-Vergleich (wie beim Abgleich gegen
 * bereits vorhandene DB-Werke weiter unten) erkennt das nicht, es entstehen
 * zwei Zeilen für dasselbe Stück. Hier deshalb VOR jedem DB-Zugriff
 * innerhalb des einen Extraktions-Ergebnisses clustern: zwei Titel gelten
 * als dasselbe Werk, wenn einer (normalisiert) im anderen enthalten ist —
 * behalten wird der LÄNGERE (ausführlichere) Titel, der Komponist wird
 * übernommen, falls nur eine der beiden Varianten ihn nennt. */
function dedupeExtractedWorks(
  works: { title?: unknown; composerFullName?: unknown }[],
): { title: string; composerFullName?: string }[] {
  const clusters: { title: string; composerFullName?: string }[] = [];
  for (const raw of works) {
    const title = typeof raw?.title === "string" ? raw.title.trim() : "";
    if (!title) continue;
    const composerFullName = typeof raw?.composerFullName === "string" ? raw.composerFullName.trim() : undefined;
    const normalized = normalizeWorkTitleSimple(title);

    const matchIndex = clusters.findIndex((c) => {
      const cNorm = normalizeWorkTitleSimple(c.title);
      return cNorm.includes(normalized) || normalized.includes(cNorm);
    });
    if (matchIndex === -1) {
      clusters.push({ title, composerFullName });
      continue;
    }
    const existing = clusters[matchIndex];
    clusters[matchIndex] = {
      title: title.length > existing.title.length ? title : existing.title,
      composerFullName: existing.composerFullName || composerFullName,
    };
  }
  return clusters;
}

/** Nutzervorgabe nach der ersten, konservativeren Version: "ich möchte,
 * dass alle nutzer meldungen, wenn vom admin so veranlasst komplett
 * gefixt werden. auch wenn es in deinen augen risky ist" — legt bei
 * eindeutiger Textevidenz fehlende Werke (+ bei Bedarf deren Komponist:in)
 * an und verknüpft sie mit der Veranstaltung. NUR admin-veranlasst (siehe
 * Datei-Kommentar) — Werk-Erkennung aus Freitext kann Duplikate oder
 * falsche Komponisten-Zuordnungen erzeugen, das soll ein Mensch bewusst
 * anstoßen, nicht ein unbeaufsichtigter Cron-Lauf. */
async function fixMissingProgram(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  report: ContentReportRow,
  adminInitiated: boolean,
): Promise<FixResult> {
  if (!adminInitiated) {
    return {
      status: "needs_manual_review",
      diagnosis:
        "Werk-/Programmänderungen legen bei Bedarf neue Werke/Komponist:innen an — das läuft nur bei einem " +
        "gezielten Klick auf \"Automatisch fixen\", nicht automatisch per Cron.",
    };
  }
  if (report.entity_type !== "event") {
    return { status: "needs_manual_review", diagnosis: "Fehlendes Programm außerhalb einer Veranstaltung wird nicht automatisch geprüft." };
  }

  const { data: event } = await supabase
    .from("events")
    .select("id, title, description_de, ticket_url, website_url")
    .eq("id", report.entity_id)
    .maybeSingle();
  if (!event) return { status: "error", diagnosis: "Veranstaltung nicht gefunden." };

  const pageUrl = (event.ticket_url as string | null) ?? (event.website_url as string | null);
  const pageText = pageUrl ? await fetchPageText(pageUrl) : null;
  const contextText = pageText
    ? `Text der Quellseite (${pageUrl}):\n${pageText}`
    : `Titel: ${event.title}\nBeschreibung: ${event.description_de ?? "(keine)"}\n(Keine externe Quellseite abrufbar — nur Titel/Beschreibung als Grundlage.)`;

  if (!hasAnyAiProviderConfigured()) {
    return { status: "needs_manual_review", diagnosis: "Kein AI-Provider-Secret konfiguriert." };
  }

  const response = await callAiFunction(
    "Du bist Teil einer redaktionellen Datenpflege für eine Klassik-Konzert-App in München. Du prüfst eine " +
      "Nutzer-Meldung ('Programminformation fehlt') und extrahierst, welche Werke laut Text aufgeführt werden. " +
      "Erfinde niemals ein Werk oder einen Komponisten, der nicht im Text steht. Sei konservativ: bei jedem " +
      "Zweifel confident=false oder das Werk weglassen.",
    `Meldungstext: ${report.message ?? "(kein Kommentar)"}\n\n${contextText}`,
    WORK_LIST_FUNCTION,
  );
  if (!response) return { status: "needs_manual_review", diagnosis: "KI-Aufruf fehlgeschlagen (alle Provider)." };
  const { args, provider } = response;

  const works = dedupeExtractedWorks(Array.isArray(args.works) ? args.works : []);
  if (args.confident !== true || works.length === 0) {
    return {
      status: "needs_manual_review",
      diagnosis: typeof args.reasoning === "string" ? args.reasoning : "KI fand kein eindeutiges Werk im verfügbaren Text.",
      aiProvider: provider,
    };
  }

  const { data: existingLinks } = await supabase.from("event_works").select("work_id").eq("event_id", report.entity_id);
  const alreadyLinkedIds = new Set((existingLinks ?? []).map((r: { work_id: string }) => r.work_id));
  const { data: nextPositionRow } = await supabase
    .from("event_works")
    .select("position")
    .eq("event_id", report.entity_id)
    .order("position", { ascending: false })
    .limit(1)
    .maybeSingle();
  let nextPosition = (nextPositionRow?.position ?? -1) + 1;

  const linked: string[] = [];
  const skipped: string[] = [];
  const fieldsChanged: { table: string; id: string; field: string; before: unknown; after: unknown }[] = [];

  for (const w of works) {
    const title = w.title;
    const composerName = w.composerFullName ?? "";
    const composer = composerName
      ? await getOrCreatePersonSimple(supabase, composerName, { event_id: report.entity_id, report_id: report.id, role: "komponist" })
      : null;
    if (composer && composer.created) {
      await supabase.from("persons").update({ roles: ["komponist"] }).eq("id", composer.id);
    }

    // Einfacher Dubletten-Schutz: exakter Titel-Abgleich (case-insensitive)
    // gegen ALLE Werke, nicht nur die dieser Veranstaltung — reicht für den
    // hier üblichen Fall (Werktitel sind meist eindeutig genug), volle
    // Fuzzy-Normalisierung wie in enrich-event-references wäre mehr aus
    // einer zweiten Edge Function dupliziert, als für diesen Zweck nötig.
    const { data: existingWork } = await supabase.from("works").select("id").ilike("title", title).maybeSingle();

    let workId: string;
    if (existingWork) {
      workId = existingWork.id;
    } else {
      const { data: createdWork, error: workError } = await supabase
        .from("works")
        .insert({ title, composer_id: composer?.id ?? null })
        .select("id")
        .single();
      if (workError || !createdWork) {
        skipped.push(`${title} (Anlegen fehlgeschlagen: ${workError?.message ?? "?"})`);
        continue;
      }
      workId = createdWork.id;
      fieldsChanged.push({ table: "works", id: workId, field: "created", before: null, after: title });
    }

    if (alreadyLinkedIds.has(workId)) {
      skipped.push(`${title} (bereits verknüpft)`);
      continue;
    }

    const { error: linkError } = await supabase
      .from("event_works")
      .insert({ event_id: report.entity_id, work_id: workId, position: nextPosition++ });
    if (linkError) {
      skipped.push(`${title} (Verknüpfen fehlgeschlagen: ${linkError.message})`);
      continue;
    }
    alreadyLinkedIds.add(workId);
    linked.push(composerName ? `${title} (${composerName})` : title);
    fieldsChanged.push({ table: "event_works", id: workId, field: "linked", before: null, after: title });
  }

  if (linked.length === 0) {
    return {
      status: "needs_manual_review",
      diagnosis: `Keines der erkannten Werke konnte verknüpft werden${skipped.length ? `: ${skipped.join("; ")}` : "."}`,
      aiProvider: provider,
    };
  }

  return {
    status: "fixed",
    diagnosis: `${args.reasoning ?? ""} (${linked.length} Werk(e) ergänzt${skipped.length ? `, ${skipped.length} übersprungen` : ""}.)`,
    actionTaken: `Programm ergänzt: ${linked.join("; ")}`,
    fieldsChanged,
    aiProvider: provider,
  };
}

const FREEFORM_FIX_FUNCTION: AiFunctionDeclaration = {
  name: "propose_freeform_fix",
  description:
    "Entscheidet frei — wie eine erfahrene Redaktion, nicht als starres Regelwerk — wie eine bereits einmal " +
    "erfolglos automatisch geprüfte Nutzer-Meldung zu behandeln ist.",
  parameters: {
    type: "object",
    properties: {
      outcome: {
        type: "string",
        description:
          "Genau eine von: 'data_fix' (ein oder mehrere Datenbank-Felder sollen korrigiert werden), 'code_bug' " +
          "(die eigentliche Ursache ist vermutlich ein Bug im Scraping-/Ingest-/App-Code, kein falscher " +
          "Datenwert), 'unclear' (auch mit freierem Urteil keine sinnvolle Entscheidung möglich).",
      },
      reasoning: { type: "string", description: "Begründung auf Deutsch: was hast du geprüft, wofür hast du dich entschieden und warum." },
      title: { type: "string", description: "Korrigierter Titel/Name, nur bei outcome=data_fix." },
      descriptionDe: { type: "string", description: "Korrigierte Beschreibung/Biografie, nur bei outcome=data_fix." },
      startDatetime: { type: "string", description: "Korrigiertes Datum/Uhrzeit als ISO-8601, nur bei Events, nur bei outcome=data_fix." },
      status: { type: "string", description: "Korrigierter Status: scheduled, cancelled, postponed oder sold_out, nur bei Events." },
      ticketUrl: { type: "string", description: "Korrigierter Ticket-Link, nur bei Events." },
      websiteUrl: { type: "string", description: "Korrigierter Website-Link." },
      nationality: { type: "string", description: "Korrigierte Nationalität, nur bei Personen." },
      birthDate: { type: "string", description: "Korrigiertes Geburtsdatum als YYYY-MM-DD, nur bei Personen." },
      deathDate: { type: "string", description: "Korrigiertes Sterbedatum als YYYY-MM-DD, nur bei Personen." },
      instrument: { type: "string", description: "Korrigiertes Hauptinstrument, nur bei Personen." },
      foundedYear: { type: "number", description: "Korrigiertes Gründungsjahr, nur bei Ensembles." },
      city: { type: "string", description: "Korrigierte Herkunfts-/Sitzstadt, nur bei Ensembles." },
      country: { type: "string", description: "Korrigiertes Herkunftsland, nur bei Ensembles." },
      addressStreet: { type: "string", description: "Korrigierte Straße samt Hausnummer, nur bei Venues." },
      addressZip: { type: "string", description: "Korrigierte Postleitzahl, nur bei Venues." },
      addressCity: { type: "string", description: "Korrigierte Stadt der Adresse, nur bei Venues." },
      phone: { type: "string", description: "Korrigierte Telefonnummer, nur bei Venues." },
      publicTransport: { type: "string", description: "Korrigierte ÖPNV-Anbindung, nur bei Venues." },
      codeBugTitle: { type: "string", description: "Kurzer Titel für die Code-Aufgabe, nur bei outcome=code_bug." },
      codeBugPrompt: {
        type: "string",
        description:
          "Nur bei outcome=code_bug: ein selbstständiger, in sich geschlossener Auftragstext für einen " +
          "Software-Entwickler ohne Kenntnis dieser Konversation — welche Datei/Funktion vermutlich betroffen " +
          "ist (falls erkennbar), was das Symptom ist, und welcher Beleg (Meldungstext, bisherige Fix-Versuche, " +
          "aktuell gespeicherte Werte) dafür spricht.",
      },
    },
    required: ["outcome", "reasoning"],
  },
};

/** Nutzerwunsch: "bei erneut versuchen soll einfach eine KI diese fehler
 * durchgehen und beheben. das ist dann wie, als würde ich dir eine
 * chatnachricht mit der fehlerkorrektur schreiben." Läuft NUR beim
 * gezielten "Erneut versuchen"-Klick (nie per Cron, siehe Datei-Kommentar
 * Punkt 4 und retry-Flag im Deno.serve-Handler) — ein Mensch hat also schon
 * einmal den ersten, konservativeren automatischen Versuch UND ggf. die
 * Selbstkritik-Runde (fixViaSourceEvidence) durchlaufen lassen und klickt
 * bewusst erneut. Anders als der Erstversuch verlangt dieser Pfad KEIN
 * wörtliches Zitat von einer Quellseite mehr — die KI bekommt stattdessen
 * den vollen Datensatz der Entität, den Meldungstext und alle bisherigen
 * Fix-Versuche und entscheidet wie ein Redakteur, dem man den Fehler in
 * einer Chatnachricht schildert. Bleibt aber weiterhin auf die Felder aus
 * ALLOWED_FIELDS beschränkt (Sicherheitsprinzip 1 bleibt in Kraft) — nur
 * die Beleg-Pflicht entfällt. Vermutet die KI stattdessen einen Code-Bug
 * (z.B. #b7: bestimmte Quellen schlagen strukturell fehl), kann sie das
 * zur Laufzeit nicht selbst reparieren (Edge Functions haben keinen Repo-/
 * Deploy-Zugriff) — stattdessen legt sie eine fertige Aufgabe in
 * code_fix_tasks an, die Claude Code beim nächsten Mal aufgreift. */
async function fixFreeform(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  report: ContentReportRow,
): Promise<FixResult> {
  const table = ENTITY_TABLE[report.entity_type];
  const allowed = ALLOWED_FIELDS[report.entity_type];

  const { data: entity, error: loadError } = await supabase.from(table).select("*").eq("id", report.entity_id).maybeSingle();
  if (loadError || !entity) {
    return { status: "error", diagnosis: `Entität nicht ladbar: ${loadError?.message ?? "nicht gefunden"}` };
  }

  if (!hasAnyAiProviderConfigured()) {
    return { status: "needs_manual_review", diagnosis: "Kein AI-Provider-Secret konfiguriert." };
  }

  const { data: history } = await supabase
    .from("content_report_fixes")
    .select("status, diagnosis, created_at")
    .eq("report_id", report.id)
    .order("created_at", { ascending: true });

  const historyRows = (history ?? []) as { status: string; diagnosis: string; created_at: string }[];
  const historyText = historyRows
    .map((h, i) => `Versuch ${i + 1} (${h.status}): ${h.diagnosis}`)
    .join("\n") || "(keine bisherigen Versuche protokolliert)";

  // Beste-Bemühung-Kontext, KEINE Pflicht mehr (anders als fixViaSourceEvidence)
  // — falls vorhanden, hilft eine echte Quellseite trotzdem bei der Einschätzung.
  const pageUrl = report.entity_type === "event"
    ? (entity.ticket_url as string | null) ?? (entity.website_url as string | null)
    : (entity.website_url as string | null);
  const pageText = pageUrl ? await fetchPageText(pageUrl) : null;

  const currentValues = Object.fromEntries(Object.entries(allowed).map(([schemaField, column]) => [schemaField, entity[column]]));

  const response = await callAiFunction(
    "Du bist ein erfahrener Redakteur einer Klassik-Konzert-App in München und bekommst eine Nutzer-Meldung " +
      "geschildert, die der automatische, konservative Erst-Check bereits geprüft hat, ohne sich sicher genug zu " +
      "fühlen (siehe Verlauf). Du darfst jetzt freier urteilen — wie ein Kollege, dem man den Fehler in einer " +
      "Chatnachricht schildert, nicht wie ein starres Regelwerk. Ein wörtliches Zitat ist NICHT mehr zwingend " +
      "nötig, wenn dir die aktuell gespeicherten Werte, der Meldungstext und der bisherige Verlauf zusammen " +
      "genug Kontext für eine plausible Korrektur geben. Bleib trotzdem ehrlich: wenn du wirklich nichts " +
      "Sinnvolles erkennst, wähle 'unclear' statt zu raten. Wenn dir die Meldung eher nach einem strukturellen " +
      "Bug in der Datenerfassung (Scraper/Import) als nach einem einzelnen falschen Wert aussieht — z.B. weil " +
      "mehrere Versuche am selben Symptom scheitern oder ein Feld systematisch fehlt/falsch befüllt wirkt — " +
      "wähle 'code_bug' und beschreibe präzise, was zu prüfen ist.",
    `Meldungsgrund: ${report.reason}\nNutzer-Kommentar: ${report.message ?? "(kein Kommentar)"}\n\n` +
      `Bisherige automatische Versuche:\n${historyText}\n\n` +
      `Aktuell gespeicherte Werte: ${JSON.stringify(currentValues)}\n\n` +
      (pageText ? `Text einer evtl. relevanten Quellseite (${pageUrl}):\n${pageText}` : "(Keine Quellseite abrufbar oder hinterlegt.)"),
    FREEFORM_FIX_FUNCTION,
  );

  if (!response) return { status: "needs_manual_review", diagnosis: "KI-Aufruf fehlgeschlagen (alle Provider)." };
  const { args, provider } = response;

  if (args.outcome === "code_bug") {
    const title = typeof args.codeBugTitle === "string" && args.codeBugTitle.trim() ? args.codeBugTitle.trim() : `Code-Bug-Verdacht: ${report.reason}`;
    const prompt = typeof args.codeBugPrompt === "string" && args.codeBugPrompt.trim()
      ? args.codeBugPrompt.trim()
      : String(args.reasoning ?? "Kein Auftragstext geliefert.");
    return {
      status: "code_bug_suspected",
      diagnosis: `${args.reasoning ?? ""} (Aufgabe für Claude Code angelegt: „${title}“)`,
      aiProvider: provider,
      codeFixTask: { title, prompt },
    };
  }

  if (args.outcome !== "data_fix") {
    return {
      status: "needs_manual_review",
      diagnosis: typeof args.reasoning === "string" ? args.reasoning : "KI konnte sich auch mit freierem Urteil nicht entscheiden.",
      aiProvider: provider,
    };
  }

  const { updates, fieldsChanged } = buildUpdatesFromProposal(args, entity, table, allowed, report.entity_id);
  if (fieldsChanged.length === 0) {
    return {
      status: "needs_manual_review",
      diagnosis: `KI entschied sich für eine Datenkorrektur, aber kein Wert bestand die Validierung oder wich vom ` +
        `gespeicherten Wert ab. Begründung: ${args.reasoning ?? "-"}`,
      aiProvider: provider,
    };
  }

  const { error: updateError } = await supabase.from(table).update(updates).eq("id", report.entity_id);
  if (updateError) return { status: "error", diagnosis: `Update fehlgeschlagen: ${updateError.message}`, aiProvider: provider };

  return {
    status: "fixed",
    diagnosis: `${args.reasoning ?? ""} (freies Urteil im Retry-Modus, ohne Zitatpflicht)`,
    actionTaken: fieldsChanged.map((f) => `${f.field}: „${f.before ?? "–"}“ → „${f.after}“`).join("; "),
    fieldsChanged,
    aiProvider: provider,
  };
}

async function fixReport(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  supabaseUrl: string,
  anonKey: string,
  report: ContentReportRow,
  adminInitiated: boolean,
  retry: boolean,
): Promise<FixResult> {
  if (retry) {
    return await fixFreeform(supabase, report);
  }
  if (report.reason === "wrong_image") {
    return await fixWrongImage(supabase, supabaseUrl, anonKey, report.entity_type, report.entity_id);
  }
  if (report.reason === "wrong_artist") {
    return await fixWrongArtist(supabase, report, adminInitiated);
  }
  if (report.reason === "missing_program") {
    return await fixMissingProgram(supabase, report, adminInitiated);
  }
  return await fixViaSourceEvidence(supabase, report);
}

Deno.serve(async (req) => {
  let body: { reportId?: unknown; limit?: unknown; adminInitiated?: unknown; retry?: unknown };
  try {
    body = await req.json();
  } catch {
    body = {};
  }
  // Nur true, wenn die aufrufende Seite es explizit setzt (admin-actions.ts
  // tut das für beide Buttons) — der Cron-Aufruf (siehe 20261006000009)
  // lässt das Feld weg und bleibt damit konservativ. Siehe Datei-Kommentar.
  const adminInitiated = body.adminInitiated === true;
  // Nur beim "Erneut versuchen"-Klick gesetzt (nie per Cron, nie beim
  // allerersten "Automatisch fixen") — schaltet auf den freieren
  // fixFreeform-Pfad um, siehe dortiger Kommentar.
  const retry = body.retry === true;

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  const supabase = createClient(supabaseUrl, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "");

  let reports: ContentReportRow[] = [];
  if (typeof body.reportId === "string") {
    const { data, error } = await supabase
      .from("content_reports")
      .select("id, entity_type, entity_id, reason, message")
      .eq("id", body.reportId)
      .maybeSingle<ContentReportRow>();
    if (error || !data) {
      return new Response(JSON.stringify({ error: error?.message ?? "Meldung nicht gefunden" }), { status: 404 });
    }
    reports = [data];
  } else {
    const limit = typeof body.limit === "number" && body.limit > 0 ? Math.min(body.limit, 20) : 5;
    // Automatischer (Cron-)Lauf: nur Meldungen, die noch NIE versucht wurden
    // — verhindert, dass ein hängengebliebenes needs_manual_review/error bei
    // jedem Cron-Tick erneut (und erfolglos) verarbeitet wird. Ein manueller
    // "Erneut versuchen"-Klick über reportId oben umgeht diese Sperre bewusst.
    const { data: pending, error } = await supabase
      .from("content_reports")
      .select("id, entity_type, entity_id, reason, message")
      .eq("status", "pending")
      .order("created_at", { ascending: true })
      .limit(limit * 3)
      .returns<ContentReportRow[]>();
    if (error) return new Response(JSON.stringify({ error: error.message }), { status: 500 });

    const { data: alreadyTried } = await supabase
      .from("content_report_fixes")
      .select("report_id")
      .in("report_id", (pending ?? []).map((r) => r.id));
    const triedIds = new Set((alreadyTried ?? []).map((r: { report_id: string }) => r.report_id));
    reports = (pending ?? []).filter((r) => !triedIds.has(r.id)).slice(0, limit);
  }

  const results: { reportId: string; status: string; diagnosis: string }[] = [];

  for (const report of reports) {
    let result: FixResult;
    try {
      result = await fixReport(supabase, supabaseUrl, anonKey, report, adminInitiated, retry);
    } catch (err) {
      result = { status: "error", diagnosis: `Unerwarteter Fehler: ${err instanceof Error ? err.message : String(err)}` };
    }

    const { data: insertedFix } = await supabase
      .from("content_report_fixes")
      .insert({
        report_id: report.id,
        status: result.status,
        diagnosis: result.diagnosis,
        action_taken: result.actionTaken ?? null,
        fields_changed: result.fieldsChanged ?? [],
        ai_provider: result.aiProvider ?? null,
      })
      .select("id")
      .single();

    if (result.status === "fixed") {
      await supabase
        .from("content_reports")
        .update({ status: "resolved", reviewed_at: new Date().toISOString() })
        .eq("id", report.id);
    }
    // needs_manual_review/error/code_bug_suspected: content_reports.status
    // bleibt 'pending' — die Redaktion sieht den Diagnose-Bericht weiterhin
    // in der Warteschlange.

    if (result.status === "code_bug_suspected" && result.codeFixTask) {
      await supabase.from("code_fix_tasks").insert({
        report_id: report.id,
        fix_id: insertedFix?.id ?? null,
        title: result.codeFixTask.title,
        prompt: result.codeFixTask.prompt,
      });
    }

    results.push({ reportId: report.id, status: result.status, diagnosis: result.diagnosis });
  }

  return new Response(JSON.stringify({ processed: results.length, results }));
});
