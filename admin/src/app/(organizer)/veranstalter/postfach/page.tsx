import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { PageHeader, PageBody } from "@/components/organizer/page-header";
import { Card, CardContent } from "@/components/organizer/ui/card";
import { Button } from "@/components/organizer/ui/button";
import { markAllNotificationsRead } from "./actions";
import { NotificationList, type NotificationRow } from "./notification-list";

export const dynamic = "force-dynamic";

const PAGE_SIZE = 50;

export default async function PostfachPage({ searchParams }: { searchParams: Promise<{ page?: string }> }) {
  const { page: pageParam } = await searchParams;
  const page = Math.max(1, Number.parseInt(pageParam ?? "1", 10) || 1);
  const supabase = await createClient();

  // Kein manueller user_id-Filter nötig — RLS liefert ausschließlich eigene
  // Zeilen (siehe "Nutzer sieht eigene Notifications" in 20261201000001).
  const [{ data, error, count }, { count: unreadCount }] = await Promise.all([
    supabase
      .from("organizer_notifications")
      .select("id, type, title, body, link_href, read_at, created_at", { count: "exact" })
      .order("created_at", { ascending: false })
      .range((page - 1) * PAGE_SIZE, page * PAGE_SIZE - 1)
      .returns<NotificationRow[]>(),
    supabase.from("organizer_notifications").select("id", { count: "exact", head: true }).is("read_at", null),
  ]);

  const notifications = data ?? [];
  const unread = { length: unreadCount ?? 0 };
  const pages = Math.max(1, Math.ceil((count ?? 0) / PAGE_SIZE));

  return (
    <div>
      <PageHeader
        eyebrow="Postfach"
        title="Benachrichtigungen"
        description={unread.length > 0 ? `${unread.length} ungelesene Benachrichtigung${unread.length === 1 ? "" : "en"}` : "Alles gelesen"}
        actions={
          unread.length > 0 && (
            <form action={markAllNotificationsRead}>
              <Button type="submit" variant="secondary" size="sm">
                Alle als gelesen markieren
              </Button>
            </form>
          )
        }
      />
      <PageBody className="mx-auto max-w-3xl">
        {error && (
          <Card>
            <CardContent className="pt-5 text-sm text-[#6B6B6B]">
              Das Postfach ist nach der nächsten Datenbank-Aktualisierung verfügbar.
            </CardContent>
          </Card>
        )}

        {!error && notifications.length === 0 && (
          <Card>
            <CardContent className="pt-5 text-sm text-[#6B6B6B]">
              Noch keine Benachrichtigungen — hier erscheinen z.B. Claim-Entscheidungen und Promotion-Freigaben.
            </CardContent>
          </Card>
        )}

        {!error && notifications.length > 0 && <NotificationList notifications={notifications} />}
        {pages > 1 && (
          <nav className="mt-6 flex items-center justify-between text-sm" aria-label="Seitennavigation">
            {page > 1 ? <Link className="font-medium text-[#2D2A6E] hover:underline" href={`/veranstalter/postfach?page=${page - 1}`}>← Neuere</Link> : <span />}
            <span className="text-[#6B6B6B]">Seite {page} von {pages}</span>
            {page < pages ? <Link className="font-medium text-[#2D2A6E] hover:underline" href={`/veranstalter/postfach?page=${page + 1}`}>Ältere →</Link> : <span />}
          </nav>
        )}
      </PageBody>
    </div>
  );
}
