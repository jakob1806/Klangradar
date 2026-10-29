import { createClient } from "@/lib/supabase/server";
import { formatMunichDateTime } from "@/lib/munich-time";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/organizer/ui/card";
import { Input } from "@/components/organizer/ui/input";
import { Label } from "@/components/organizer/ui/label";
import { SubmitButton } from "@/components/organizer/submit-button";
import { ActionForm } from "@/components/organizer/action-form";
import { reportCastChange } from "../cast-actions";

// Erstellt von Claude Code (Nutzerwunsch 29.10.2026): Besetzungsänderung
// melden — z. B. kurzfristige Umbesetzung. Bisherige Meldungen darunter.
export async function CastChangeCard({ eventId }: { eventId: string }) {
  const supabase = await createClient();
  const { data } = await supabase.rpc("organizer_cast_changes", { p_event_id: eventId });
  const changes = (data ?? []) as { changed_at: string; removed: string | null; added: string | null }[];

  return (
    <Card>
      <CardHeader>
        <CardTitle>Besetzungsänderung melden</CardTitle>
        <CardDescription>
          Alle, die diesen Termin in der App gemerkt haben, bekommen eine Mitteilung.
        </CardDescription>
      </CardHeader>
      <CardContent className="flex flex-col gap-5">
        <ActionForm action={reportCastChange.bind(null, eventId)} className="grid gap-3 sm:grid-cols-2">
          <div className="flex flex-col gap-1.5">
            <Label htmlFor="cast-added">Neu dabei</Label>
            <Input id="cast-added" name="added" maxLength={200} placeholder="z. B. Anna Prohaska (Sopran)" />
          </div>
          <div className="flex flex-col gap-1.5">
            <Label htmlFor="cast-removed">Nicht mehr dabei</Label>
            <Input id="cast-removed" name="removed" maxLength={200} placeholder="z. B. Christiane Karg" />
          </div>
          <div className="sm:col-span-2">
            <SubmitButton size="sm" pendingLabel="Melde …">
              Änderung melden
            </SubmitButton>
          </div>
        </ActionForm>
        {changes.length > 0 && (
          <div className="flex flex-col gap-2 border-t border-[#F0F0F0] pt-4">
            <p className="text-[13px] font-medium text-[#111111]">Bisher gemeldet</p>
            <ul className="flex flex-col gap-1.5 text-[13px] text-[#4A4A4A]">
              {changes.map((change) => (
                <li key={change.changed_at}>
                  <span className="text-[#6B6B6B]">{formatMunichDateTime(change.changed_at)}:</span>{" "}
                  {[change.added && `neu: ${change.added}`, change.removed && `nicht mehr: ${change.removed}`].filter(Boolean).join(" · ")}
                </li>
              ))}
            </ul>
          </div>
        )}
      </CardContent>
    </Card>
  );
}
