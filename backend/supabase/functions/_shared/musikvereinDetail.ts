// Erstellt von Claude Code (25.10.2026): Parser für die öffentliche
// Spielplan-JSON des Musikvereins (spielplan.musikverein.at/e/<id>.json).
// Liefert Werke in Konzertreihenfolge (Pause = "***"), Mitwirkende mit
// Instrument/Funktion und – falls vorhanden – den Langtext.
import type { EventParticipantCandidate } from "./eventParticipantResolution.ts";

export interface MusikvereinWork {
  composerName: string | null;
  title: string;
  position: number;
  afterIntermission: boolean;
}

export interface MusikvereinDetail {
  works: MusikvereinWork[];
  participants: EventParticipantCandidate[];
  description: string | null;
}

const ENSEMBLE_PROFESSIONS = /orchester|ensemble|chor|quartett|quintett|trio|band|philharmoni|symphoni|sinfoni|consort|akademie/i;

export function musikvereinId(url: string | null | undefined): string | null {
  return url?.match(/musikverein\.at\/konzert\/?\?id=([0-9a-f]+)/i)?.[1] ?? null;
}

export function stripHtml(html: string): string {
  let s = html.replace(/<br\s*\/?>/gi, "\n").replace(/<\/p>/gi, "\n\n");
  let prev: string;
  do {
    prev = s;
    s = s.replace(/<[^<>]*>/g, " ");
  } while (s !== prev);
  return s.replace(/[<>]/g, "")
    .replace(/&nbsp;/g, " ").replace(/&amp;/g, "&").replace(/&quot;/g, '"').replace(/&#39;/g, "'")
    .replace(/[ \t]+/g, " ").replace(/ *\n */g, "\n").replace(/\n{3,}/g, "\n\n").trim();
}

// deno-lint-ignore no-explicit-any
export function parseMusikvereinDetail(data: any): MusikvereinDetail {
  const booking = data?.booking?.data?.[0] ?? {};
  // deno-lint-ignore no-explicit-any
  const program: any[] = [...(data?.program?.data ?? [])].sort((a, b) => Number(a.order) - Number(b.order));
  const works: MusikvereinWork[] = [];
  let afterIntermission = false;
  for (const item of program) {
    const title = String(item.opus_titel_D ?? "").trim();
    const composer = String(item.composer_author ?? "").trim();
    if (title === "***" || composer === "***") { afterIntermission = true; continue; }
    if (!title || Number(item.is_text) === 1 || Number(item.is_encore) === 1) continue;
    works.push({ composerName: composer || null, title, position: works.length + 1, afterIntermission });
  }

  const participants: EventParticipantCandidate[] = [];
  for (const c of data?.cast?.data ?? []) {
    const name = String(c.name_D ?? "").trim();
    if (!name) continue;
    const profession = String(c.profession_D ?? "").trim();
    const role = String(c.role_D ?? "").trim();
    const isEnsemble = ENSEMBLE_PROFESSIONS.test(profession) || (!profession && ENSEMBLE_PROFESSIONS.test(name));
    const type = isEnsemble ? "ensemble" : "person";
    participants.push({ name, profileUrl: null, role: [profession, role].filter(Boolean).join(" · ") || null, type });
  }

  const longText = Object.entries(booking)
    .filter(([k, v]) => /^comm_descr_long_.*_D$/.test(k) && typeof v === "string" && v.trim())
    .map(([, v]) => stripHtml(v as string))
    .filter((t) => t.length > 40)
    .join("\n\n");
  return { works, participants, description: longText || null };
}
