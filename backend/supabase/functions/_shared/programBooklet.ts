// Erstellt von Claude Code (Nutzerwunsch 24.10.2026): Programmhefte, falls
// die Veranstalter sie online anbieten, auf der Konzertseite verlinken.
// Erkennt Links, deren Text oder Ziel nach Programmheft aussieht (PDF,
// issuu/yumpu/calameo, "Programmheft", "Abendprogramm", "Programme booklet").
// Saison-Broschüren und Spielzeithefte werden bewusst ausgeschlossen.

const LINK_PATTERN = /<a\b[^>]*href="([^"]+)"[^>]*>([\s\S]*?)<\/a>/gi;
const TEXT_HINT = /(programmheft|abendprogramm|programm\s*(zum|als)\s*(download|pdf)|digitales\s+programm|program(me)?\s*(booklet|notes\s*\(pdf\))|konzertprogramm)/i;
const HREF_HINT = /(programmheft|abendprogramm|program[-_]?booklet|issuu\.com|yumpu\.com|calameo\.com)/i;
const EXCLUDE = /(saison|spielzeit|season|jahresprogramm|abo|brosch|newsletter|agb|datenschutz|impressum)/i;

function plain(value: string): string {
  return value.replace(/<[^>]+>/g, " ").replace(/&nbsp;/g, " ").replace(/\s+/g, " ").trim();
}

export function findProgramBooklet(html: string, pageUrl: string): string | null {
  for (const match of html.matchAll(LINK_PATTERN)) {
    const href = match[1];
    const text = plain(match[2]);
    const isPdf = /\.pdf(\?|#|$)/i.test(href);
    const hinted = TEXT_HINT.test(text) || HREF_HINT.test(href) || (isPdf && /programm|program/i.test(href + " " + text));
    if (!hinted || EXCLUDE.test(href + " " + text)) continue;
    try {
      return new URL(href, pageUrl).toString();
    } catch {
      continue;
    }
  }
  return null;
}

// deno-lint-ignore no-explicit-any
export async function saveProgramBooklet(supabase: any, eventId: string, html: string, pageUrl: string): Promise<void> {
  const url = findProgramBooklet(html, pageUrl);
  if (!url) return;
  await supabase.from("events").update({ program_booklet_url: url, booklet_facts_checked_at: null }).eq("id", eventId).is("program_booklet_url", null);
}
