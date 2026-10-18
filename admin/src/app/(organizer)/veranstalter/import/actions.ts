"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { createAdminClient } from "@/lib/supabase/admin";
import { isAllowedFeedUrl, previewFeed, type FeedPreview } from "@/lib/feed-preview";
import { portalEmail, redaktionEmail, sendPortalEmail } from "@/lib/portal-email";
import { getEventOrganizerOptions } from "../event-organizer-context";

export type FeedFormState = { error?: string; preview?: FeedPreview; url?: string; submitted?: true };

const MAX_BYTES = 3_000_000;

async function loadFeed(raw: string): Promise<{ url?: string; preview?: FeedPreview; error?: string }> {
  const url = isAllowedFeedUrl(raw);
  if (!url) return { error: "Bitte gib eine öffentliche Adresse an, die mit https:// (oder webcal://) beginnt." };
  let text: string;
  try {
    const response = await fetch(url, {
      headers: { "user-agent": "KlangradarBot/1.0 (+https://klangradar.com)", accept: "text/calendar, application/rss+xml, application/xml, text/html;q=0.8, */*;q=0.5" },
      signal: AbortSignal.timeout(10_000),
      redirect: "follow",
      cache: "no-store",
    });
    if (!response.ok) return { error: `Die Adresse antwortet mit Fehler ${response.status}.` };
    const length = Number(response.headers.get("content-length") ?? 0);
    if (length > MAX_BYTES) return { error: "Die Datei ist zu groß (über 3 MB)." };
    text = (await response.text()).slice(0, MAX_BYTES);
  } catch {
    return { error: "Die Adresse konnte nicht geladen werden (Zeitüberschreitung oder nicht erreichbar)." };
  }
  const preview = previewFeed(text);
  if (!preview || preview.count === 0) {
    return { error: "Unter dieser Adresse haben wir keine Termine gefunden. Unterstützt werden iCal-Kalender (.ics), RSS-Feeds und Webseiten mit schema.org-Event-Daten." };
  }
  return { url: url.toString(), preview };
}

/** Schritt 1: Adresse prüfen und Vorschau zeigen. Schritt 2 (submit=1): einreichen. */
export async function checkOrSubmitFeed(_previous: FeedFormState, formData: FormData): Promise<FeedFormState> {
  const raw = String(formData.get("url") ?? "");
  const organizerId = String(formData.get("organizer_id") ?? "");
  const submit = formData.get("submit") === "1";

  const organizers = await getEventOrganizerOptions();
  const organizer = organizers.find((o) => o.id === organizerId);
  if (!organizer) return { error: "Bitte wähle die Institution, zu der die Termine gehören." };

  const result = await loadFeed(raw);
  if (result.error || !result.url || !result.preview) return { error: result.error };
  if (!submit) return { preview: result.preview, url: result.url };

  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return { error: "Bitte melde dich erneut an." };

  // sources ist per RLS nur für die Redaktion schreibbar; die Berechtigung
  // für die Institution ist oben über getEventOrganizerOptions geprüft.
  const admin = createAdminClient();
  const { data: existing } = await admin.from("sources").select("id, organizer_id").eq("url", result.url).maybeSingle();
  if (existing) {
    return { error: existing.organizer_id === organizerId ? "Diese Adresse ist bereits eingereicht." : "Diese Adresse wird bereits von Klangradar gelesen." };
  }
  const { error } = await admin.from("sources").insert({
    name: `${organizer.name} (Self-Service ${result.preview.type === "ical" ? "iCal" : result.preview.type === "rss" ? "RSS" : "Webseite"})`,
    type: result.preview.type,
    url: result.url,
    organizer_id: organizerId,
    status: "under_review",
    crawl_frequency_minutes: 720,
    legal_basis: "Vom Veranstalter selbst eingereicht",
    config: { selfService: true, submittedBy: user.id, submittedAt: new Date().toISOString(), previewCount: result.preview.count },
  });
  if (error) return { error: "Die Quelle konnte nicht gespeichert werden. Bitte versuche es später erneut." };

  await sendPortalEmail(
    redaktionEmail(),
    portalEmail({
      subject: `Neuer Termin-Feed von ${organizer.name}`,
      eyebrow: "Redaktion · Self-Service-Import",
      title: "Ein Veranstalter hat einen Feed eingereicht",
      paragraphs: [`${organizer.name} möchte Termine automatisch über einen ${result.preview.type.toUpperCase()}-Feed liefern. Bitte prüfen und die Quelle aktivieren.`],
      facts: [["Adresse", result.url], ["Erkannte Termine", String(result.preview.count)], ["Beispiel", result.preview.samples[0]?.title ?? "–"]],
      cta: { label: "Quellen öffnen", href: "/sources" },
      footer: "Interne Benachrichtigung der Klangradar-Redaktion.",
    }),
  );

  revalidatePath("/veranstalter/import");
  return { submitted: true };
}

export async function removeFeed(formData: FormData): Promise<void> {
  const sourceId = String(formData.get("source_id") ?? "");
  const organizerIds = (await getEventOrganizerOptions()).map((o) => o.id);
  if (!sourceId || !organizerIds.length) return;
  const admin = createAdminClient();
  // Pausieren statt Löschen: bereits importierte Termine verweisen auf die Quelle.
  await admin.from("sources").update({ status: "paused" }).eq("id", sourceId).in("organizer_id", organizerIds).eq("config->>selfService", "true");
  revalidatePath("/veranstalter/import");
}
