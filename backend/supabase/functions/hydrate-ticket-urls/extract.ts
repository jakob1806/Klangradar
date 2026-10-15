// Findet auf einer Veranstaltungsseite den konzertbezogenen Kauf-Link.
// Nur Links mit erkennbarer Event-/Vorstellungs-ID — allgemeine Shop- oder
// Info-Seiten ("/shop", "Ticketinformationen") werden bewusst ignoriert,
// sie würden beim einzelnen Konzert in die Irre führen.

const EVENT_LINK_PATTERNS: RegExp[] = [
  /https?:\/\/[^"'\s<>]*webticket\/shop\?[^"'\s<>]*event=\d+[^"'\s<>]*/gi, // Eventim-Webshops (DSO, Elbphilharmonie …)
  /https?:\/\/[^"'\s<>]*\/link\/event\/\d+[^"'\s<>]*/gi, // München Ticket / CTS-Shops
  /https?:\/\/(?:www\.)?eventim\.[a-z.]+\/event\/[^"'\s<>]+/gi,
  /https?:\/\/(?:www\.)?reservix\.[a-z.]+\/tickets-[^"'\s<>]+/gi,
  /https?:\/\/[^"'\s<>]*\/(?:performance|vorstellung|event)[s]?\/\d{3,}[^"'\s<>]*/gi,
  /https?:\/\/[^"'\s<>]*[?&](?:id_vorstellung|vorstellung|performanceid|eventid|event_id)=\d+[^"'\s<>]*/gi,
];

const MONTHS = ["januar", "februar", "märz", "april", "mai", "juni", "juli", "august", "september", "oktober", "november", "dezember"];

function decodeEntities(value: string): string {
  // &amp; zuletzt auflösen, sonst würde "&amp;#47;" doppelt dekodiert.
  return value.replace(/&#x2F;/gi, "/").replace(/&#47;/g, "/").replace(/&amp;/g, "&");
}

/** Datums-Schreibweisen, die neben einem passenden Link stehen könnten. */
export function dateNeedles(start: Date): string[] {
  const parts = new Intl.DateTimeFormat("de-DE", { timeZone: "Europe/Berlin", day: "numeric", month: "numeric", year: "numeric" }).formatToParts(start);
  const day = Number(parts.find((p) => p.type === "day")!.value);
  const month = Number(parts.find((p) => p.type === "month")!.value);
  const year = parts.find((p) => p.type === "year")!.value;
  const dd = String(day).padStart(2, "0");
  const mm = String(month).padStart(2, "0");
  return [`${dd}.${mm}.${year}`, `${day}.${month}.${year}`, `${dd}.${mm}.`, `${day}. ${MONTHS[month - 1]}`, `${year}-${mm}-${dd}`];
}

export function extractTicketUrl(html: string, start: Date): string | null {
  const found = new Map<string, number>(); // URL -> erste Fundstelle
  for (const pattern of EVENT_LINK_PATTERNS) {
    for (const match of html.matchAll(pattern)) {
      const url = decodeEntities(match[0]).replace(/[)"'.,;]+$/, "");
      if (/\.(css|js|png|jpe?g|svg|webp|woff2?)(\?|$)/i.test(url)) continue;
      if (!found.has(url)) found.set(url, match.index ?? 0);
    }
  }
  if (found.size === 0) return null;
  if (found.size === 1) return [...found.keys()][0];
  // Mehrere Termine auf einer Seite: den Link nehmen, in dessen Umfeld das
  // Datum dieses Konzerts steht. Sonst lieber keinen als einen falschen.
  // Entscheidend ist das Datum, das dem Link am nächsten VORANGEHT.
  const needles = dateNeedles(start).map((n) => n.toLowerCase());
  const lower = html.toLowerCase();
  const datePattern = /\b\d{1,2}\.\s?\d{1,2}\.\s?\d{4}\b|\b\d{4}-\d{2}-\d{2}\b|\b\d{1,2}\.\s(?:januar|februar|märz|april|mai|juni|juli|august|september|oktober|november|dezember)\b/g;
  const matching = [...found.entries()].filter(([, index]) => {
    const before = lower.slice(Math.max(0, index - 600), index);
    const dates = [...before.matchAll(datePattern)].map((m) => m[0].replace(/\s/g, ""));
    const nearest = dates.at(-1);
    if (!nearest) return false;
    return needles.some((needle) => needle.replace(/\s/g, "") === nearest || needle.replace(/\s/g, "").startsWith(nearest));
  });
  return matching.length === 1 ? matching[0][0] : null;
}
