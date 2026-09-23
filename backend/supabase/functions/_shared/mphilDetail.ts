import type { EventParticipantCandidate } from "./eventParticipantResolution.ts";

// Live-Struktur einer Münchner-Philharmoniker-Konzert-Detailseite
// (mphil.de/en/concerts-tickets/calendar/concerts/<slug>, verifiziert am
// 2026-09-23 gegen .../zemlinsky-mozart-mendelssohn-bartholdy-2026-09-25-
// 19-30-00 NACH einem Website-Relaunch): die Besetzungsliste steckt jetzt in
// <li class="m-mphil-concert-detail__person ..."> ("concert-detail", nicht
// mehr "concertlist"). Der alte "m-mphil-concertlist__person"-Klassenname
// existiert weiterhin, gehört aber jetzt zur "Weitere Veranstaltungen"-
// Karussell-Sektion am Seitenende, die auf JEDER Konzertseite die Besetzung
// ANDERER, unverwandter Konzerte einblendet — der alte Parser griff genau
// diese Sektion ab und schrieb dadurch systematisch falsche Mitwirkende in
// die DB (Nutzerfeedback: "teilweise falsche Besetzungen/Mitwirkende").
// Name steht je nach Person entweder in <a class="m-mphil-concert-detail__
// person-link --wrap" href="...bio-slug"><span class="...__person-link-
// title">Name</span></a> (mit Bio-Link) oder in <p class="m-mphil-concert-
// detail__person-link -inactive">Name</p> (ohne Bio-Link, z. B. Gastensembles
// wie "Mitglieder der Münchner Philharmoniker"). Die Rolle steckt verschachtelt
// in <span class="...__instrument"><span class="nonbold small">Rolle</span>
// </span>.
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

const PERSON_LI_PATTERN = /<li class="m-mphil-concert-detail__person[^"]*">([\s\S]*?)<\/li>/g;
const ROLE_PATTERN =
  /<span class="m-mphil-concert-detail__instrument">[\s\S]*?<span class="nonbold small">([\s\S]*?)<\/span>/;
const NAME_LINK_PATTERN = /<span class="m-mphil-concert-detail__person-link-title">([\s\S]*?)<\/span>/;
const NAME_PLAIN_PATTERN = /<p class="m-mphil-concert-detail__person-link[^"]*">([\s\S]*?)<\/p>/;
const BIO_LINK_PATTERN = /<a class="m-mphil-concert-detail__person-link[^"]*" href="([^"]+)">/;

// Immer der Hausorchester dieser Quelle — taucht in der Besetzungsliste
// selbst nie als eigener Eintrag auf (nur Dirigent:in/Solist:innen stehen
// dort), muss deshalb explizit ergänzt werden.
const RESIDENT_ENSEMBLE = "Münchner Philharmoniker";

export function parseMphilEventDetail(html: string, pageUrl: string): MphilEventDetail {
  const participants: EventParticipantCandidate[] = [];
  for (const match of html.matchAll(PERSON_LI_PATTERN)) {
    const block = match[1];
    const name = (block.match(NAME_LINK_PATTERN)?.[1] ?? block.match(NAME_PLAIN_PATTERN)?.[1])
      ?.replace(/\s+/g, " ").trim();
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
