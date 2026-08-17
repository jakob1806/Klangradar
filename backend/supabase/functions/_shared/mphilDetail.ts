import type { EventParticipantCandidate } from "./eventParticipantResolution.ts";

// Live-Struktur einer Münchner-Philharmoniker-Konzert-Detailseite
// (mphil.de/en/concerts-tickets/calendar/concerts/<slug>, verifiziert am
// 2026-08-14 gegen .../brahms-schostakowitsch-2026-08-30-21-00-00):
// normales serverseitig gerendertes HTML, jede Person steckt in einem
// eigenen <li class="m-mphil-concertlist__person ..."> mit eingebettetem
// Modal (Name als <h2>, Bio-Link als <a class="e-button-primary" href=
// "/en/ueber-uns/musicians/details/<slug>">) — Modal und sichtbarer
// Listeneintrag liegen im SELBEN <li>, kein separates Matching über
// aria-controls/id über das Dokument hinweg nötig.
//
// Anders als staatsoper.de/brso.de: og:image ist auf JEDER Konzertseite
// dasselbe generische Logo-SVG (".../Icons/Logos/default.svg", jetzt über
// isLikelyGenericImage()/imageValidation.ts gefiltert) — es gibt hier kein
// eigenes Eventfoto zu extrahieren. Der eigentliche Mehrwert dieser Quelle
// ist die zuverlässige Bio-Link-Rückverlinkung (persons.website_url), über
// die die bestehende offizielle-Website-Bildrecherche (research-entity-
// image/officialSiteImageSearch.ts) ein sauberes Porträt findet — genau wie
// bei der Staatsoper (siehe staatsoperDetail.ts-Kommentar).
export interface MphilEventDetail {
  participants: EventParticipantCandidate[];
}

const PERSON_LI_PATTERN = /<li class="m-mphil-concertlist__person[^"]*">([\s\S]*?)<\/li>/g;
const ROLE_PATTERN = /<span class="m-mphil-concertlist__instrument">([\s\S]*?)<\/span>/;
const NAME_PATTERN = /<span class="m-mphil-concertlist__person-link-title">([\s\S]*?)<\/span>/;
const BIO_LINK_PATTERN = /<a class="e-button-primary" href="([^"]+)">/;

// Immer der Hausorchester dieser Quelle — taucht in der Besetzungsliste
// selbst nie als eigener Eintrag auf (nur Dirigent:in/Solist:innen stehen
// dort), muss deshalb explizit ergänzt werden.
const RESIDENT_ENSEMBLE = "Münchner Philharmoniker";

export function parseMphilEventDetail(html: string, pageUrl: string): MphilEventDetail {
  const participants: EventParticipantCandidate[] = [];
  for (const match of html.matchAll(PERSON_LI_PATTERN)) {
    const block = match[1];
    const name = block.match(NAME_PATTERN)?.[1]?.replace(/\s+/g, " ").trim();
    if (!name) continue;
    const roleRaw = block.match(ROLE_PATTERN)?.[1]?.replace(/\s+/g, " ").trim() ?? null;
    const bioLink = block.match(BIO_LINK_PATTERN)?.[1] ?? null;
    let profileUrl: string | null = null;
    if (bioLink) {
      try {
        profileUrl = new URL(bioLink, pageUrl).toString();
      } catch {
        profileUrl = null;
      }
    }
    // Live-Fund: Gastensembles (z.B. "Philharmonischer Chor München") stehen
    // im selben <li>-Markup wie Solist:innen, aber OHNE eigenen
    // <span class="...__instrument">-Eintrag — Personen haben diesen immer
    // (Rolle/Instrument ist auf mphil.de Pflichtangabe). Ohne diese
    // Unterscheidung wurde ein Chor fälschlich als Person angelegt.
    if (!roleRaw) {
      participants.push({ name, profileUrl: null, role: null, type: "ensemble" });
      continue;
    }
    participants.push({ name, profileUrl, role: classifyRole(roleRaw), type: "person" });
  }

  if (participants.length > 0) {
    participants.push({ name: RESIDENT_ENSEMBLE, profileUrl: null, role: null, type: "ensemble" });
  }

  return { participants };
}

function classifyRole(roleRaw: string): "dirigent" | "chorleiter" | "solist" {
  if (/conductor|dirigent/i.test(roleRaw)) return "dirigent";
  if (/chor(us|leitung|leiter)/i.test(roleRaw)) return "chorleiter";
  return "solist";
}
