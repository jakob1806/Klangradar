"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";

// Erstellt von Claude Code (31.10.2026): nicht zugeordnete Spielstätte als
// Alias einer bestehenden Spielstätte speichern; der nächste Import ordnet
// die Termine dann zu.
export async function addVenueAlias(alias: string, formData: FormData) {
  const venueId = String(formData.get("venue_id") ?? "");
  if (!venueId) throw new Error("Bitte eine Spielstätte wählen.");
  const supabase = await createClient();
  const { error } = await supabase.rpc("admin_add_venue_alias", { p_venue_id: venueId, p_alias: alias });
  if (error) throw new Error(error.message);
  revalidatePath("/source-health");
}
