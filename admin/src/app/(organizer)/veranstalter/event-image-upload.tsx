"use client";
import { useRef, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { addOrganizerEventImage } from "./events/actions";
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "@/components/organizer/ui/card";
import { Button } from "@/components/organizer/ui/button";
const ACCEPTED = ["image/jpeg", "image/png", "image/webp"];
export function EventImageUpload({ eventId, userId }: { eventId: string; userId: string }) { const ref = useRef<HTMLInputElement>(null); const [message, setMessage] = useState<string | null>(null); const [busy, setBusy] = useState(false); async function upload() { const file = ref.current?.files?.[0]; if (!file) return; if (!ACCEPTED.includes(file.type) || file.size > 5 * 1024 * 1024) { setMessage("Bitte JPEG, PNG oder WebP bis 5 MB wählen."); return; } setBusy(true); setMessage(null); try { const supabase = createClient(); const ext = file.name.split(".").pop() || "jpg"; const path = `organizer-event-images/${userId}/${crypto.randomUUID()}.${ext}`; const { error } = await supabase.storage.from("entity-photos").upload(path, file, { cacheControl: "3600", upsert: false }); if (error) throw error; const { data } = supabase.storage.from("entity-photos").getPublicUrl(path); await addOrganizerEventImage(eventId, data.publicUrl); setMessage("Bild hinzugefügt."); if (ref.current) ref.current.value = ""; } catch (error) { setMessage(error instanceof Error ? error.message : "Upload fehlgeschlagen."); } finally { setBusy(false); } } return (
  <Card>
    <CardHeader>
      <CardTitle>Eventbild</CardTitle>
      <CardDescription>JPEG, PNG oder WebP, maximal 5 MB.</CardDescription>
    </CardHeader>
    <CardContent className="flex flex-wrap items-center gap-2">
      <input ref={ref} type="file" accept="image/jpeg,image/png,image/webp" className="text-sm text-[#4a4550]" />
      <Button type="button" disabled={busy} onClick={upload} size="sm">{busy ? "Lädt hoch…" : "Bild hinzufügen"}</Button>
      {message && <p className="w-full text-sm text-[#4a4550]">{message}</p>}
    </CardContent>
  </Card>
); }
