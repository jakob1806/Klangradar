import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { ensureCoverImage } from "../_shared/imagePipeline.ts";

const VENUE_ID = "df97bb11-57b4-4cbe-b513-e3db4c2074ba";
const SOURCE_URL = "https://commons.wikimedia.org/wiki/Special:Redirect/file/2019-01-26_Bayerische_Nationaltheater_03.jpg?width=1600";

Deno.serve(async (req) => {
  if (req.method !== "POST") return response({ error: "method not allowed" }, 405);
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  );

  const imageId = await ensureCoverImage(supabase, {
    sourceUrl: SOURCE_URL,
    sourcePageUrl: "https://commons.wikimedia.org/wiki/File:2019-01-26_Bayerische_Nationaltheater_03.jpg",
    sourceName: "Wikimedia Commons",
    originType: "venue",
    originId: VENUE_ID,
    licenseStatus: "confirmed_free",
    needsReview: false,
    matchReason: "Hochauflösendes Venue-Fallback für das Nationaltheater München",
  });
  if (!imageId) return response({ error: "image pipeline failed" }, 500);

  const { data: image, error: imageError } = await supabase.from("images")
    .select("storage_path,width,height").eq("id", imageId).single();
  if (imageError || !image?.storage_path) return response({ error: imageError?.message ?? "storage path missing" }, 500);
  const { error: priorityError } = await supabase.from("images")
    .update({ sort_order: -1, quality_status: "valid" }).eq("id", imageId);
  if (priorityError) return response({ error: priorityError.message }, 500);
  const publicUrl = supabase.storage.from("ingested-images").getPublicUrl(image.storage_path).data.publicUrl;

  const { error: venueError } = await supabase.from("venues").update({ photo_url: publicUrl }).eq("id", VENUE_ID);
  if (venueError) return response({ error: venueError.message }, 500);

  // Nur echte Venue-Fallbacks ersetzen. Eigene Eventbilder bleiben
  // unangetastet; ebenso Personen-/Ensemble-/Werk-Fallbacks.
  const { data: oldVenueImages } = await supabase.from("images").select("id")
    .eq("origin_type", "venue").eq("origin_id", VENUE_ID).neq("id", imageId);
  const oldIds = (oldVenueImages ?? []).map((row: { id: string }) => row.id);
  if (oldIds.length > 0) {
    await supabase.from("events").update({ primary_image_id: imageId }).in("primary_image_id", oldIds);
  }

  return response({ imageId, publicUrl, width: image.width, height: image.height, replacedFallbacks: oldIds.length });
});

function response(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}
