"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";

export interface WorkImageReusePageResult {
  checkedInPage: number;
  filledInPage: number;
  totalCount: number;
  done: boolean;
}

function functionsUrl(path: string) {
  return `${process.env.NEXT_PUBLIC_SUPABASE_URL}/functions/v1/${path}`;
}

/**
 * Prüft EINE Seite von Veranstaltungen ohne eigenes Bild auf einen
 * passenden Werk-Bild-Spender (siehe backend/supabase/functions/
 * _shared/workImageReuse.ts) und verknüpft ihn, falls gefunden. Seitenweise
 * aus demselben Grund wie beim Künstler-Namensaudit: bei vielen bildlosen
 * Veranstaltungen reißt ein einziger Aufruf den Timeout.
 */
export async function runWorkImageReusePage(offset: number): Promise<WorkImageReusePageResult> {
  const supabase = await createClient();
  const { data: userData, error: userError } = await supabase.auth.getUser();
  if (userError || !userData.user || userData.user.is_anonymous) {
    throw new Error("Die Admin-Sitzung ist abgelaufen. Bitte erneut anmelden.");
  }
  const { data: sessionData, error: sessionError } = await supabase.auth.getSession();
  const accessToken = sessionData.session?.access_token;
  if (sessionError || !accessToken) {
    throw new Error("Die Admin-Sitzung konnte nicht gelesen werden. Bitte erneut anmelden.");
  }

  const anonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ?? "";
  let response: Response;
  try {
    response = await fetch(functionsUrl("backfill-work-image-reuse"), {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        apikey: anonKey,
        Authorization: `Bearer ${accessToken}`,
      },
      body: JSON.stringify({ offset }),
      signal: AbortSignal.timeout(90_000),
    });
  } catch (err) {
    const timedOut = err instanceof Error && err.name === "TimeoutError";
    throw new Error(timedOut ? "Zeitüberschreitung — bitte erneut versuchen." : `Prüfung nicht erreichbar: ${err}`);
  }

  const data: unknown = await response.json().catch(() => null);
  if (!response.ok || !data || typeof data !== "object") {
    const message = data && typeof data === "object" && "error" in data && typeof data.error === "string"
      ? data.error
      : `Prüfung fehlgeschlagen (HTTP ${response.status}).`;
    throw new Error(message);
  }

  const result = data as Record<string, unknown>;
  return {
    checkedInPage: typeof result.checkedInPage === "number" ? result.checkedInPage : 0,
    filledInPage: typeof result.filledInPage === "number" ? result.filledInPage : 0,
    totalCount: typeof result.totalCount === "number" ? result.totalCount : 0,
    done: result.done === true,
  };
}

export async function finishWorkImageReuse(): Promise<void> {
  revalidatePath("/work-image-reuse");
}

/**
 * Lehnt eine automatische Werk-Bild-Verknüpfung ab: markiert sie dauerhaft
 * als "rejected" (verhindert erneute Anwendung bei künftigen Ingest-/
 * Backfill-Läufen, siehe applyWorkImageReuse()) und entfernt das Bild von
 * der Veranstaltung, sofern es dort noch aktiv gesetzt ist — nur wenn
 * primary_image_id noch exakt diesem übernommenen Bild entspricht, damit
 * eine zwischenzeitliche manuelle Bildänderung nicht überschrieben wird.
 */
export async function rejectWorkImageReuse(flagId: string): Promise<void> {
  const supabase = await createClient();
  const { data: flag, error: flagError } = await supabase
    .from("event_image_reuse")
    .select("event_id, image_id")
    .eq("id", flagId)
    .maybeSingle();
  if (flagError) throw new Error(flagError.message);
  if (!flag) throw new Error("Verknüpfung wurde nicht gefunden.");

  const { error: updateError } = await supabase
    .from("event_image_reuse")
    .update({ status: "rejected" })
    .eq("id", flagId);
  if (updateError) throw new Error(updateError.message);

  if (flag.image_id) {
    const { data: event } = await supabase
      .from("events")
      .select("primary_image_id")
      .eq("id", flag.event_id)
      .maybeSingle();
    if (event?.primary_image_id === flag.image_id) {
      const { error: clearError } = await supabase
        .from("events")
        .update({ primary_image_id: null })
        .eq("id", flag.event_id);
      if (clearError) throw new Error(clearError.message);
    }
  }

  revalidatePath("/work-image-reuse");
}
