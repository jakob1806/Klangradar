import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { AdminPageHeader } from "@/components/admin-kit";
import { QuickReview, type QueueItem } from "./quick-review";

// Erstellt von Claude Code (Konzept Bildabdeckung, 01.11.2026): Schnellprüfung
// für Bildkandidaten, automatisch erkannte Fehlzuordnungen und Meldungen
// "Falsches Bild" aus der App – sortiert nach Wirkung (kommende Konzerte).
export const dynamic = "force-dynamic";

export default async function ImageQuickReviewPage() {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("admin_image_review_queue", { p_limit: 300 });
  const items = (data ?? []) as QueueItem[];
  return (
    <div className="p-8">
      <AdminPageHeader
        title="Bilder prüfen"
        description="Ein Bild nach dem anderen, wichtigste zuerst. J = übernehmen bzw. Bild stimmt, N = verwerfen bzw. Bild entfernen, Pfeiltasten = weiter."
      >
        <Link href="/media" className="text-sm font-medium text-[#2D2A6E] hover:underline">
          Zur Medienübersicht
        </Link>
      </AdminPageHeader>
      {error && <p className="mt-4 text-sm text-amber-700">Konnte die Warteschlange nicht laden: {error.message}</p>}
      <QuickReview items={items} />
    </div>
  );
}
