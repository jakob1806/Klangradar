import { createClient } from "@/lib/supabase/server";
import { PageHeader, PageBody } from "@/components/organizer/page-header";
import { Card, CardContent } from "@/components/organizer/ui/card";
import { Button } from "@/components/organizer/ui/button";
import { markAllNotificationsRead } from "./actions";
import { NotificationList, type NotificationRow } from "./notification-list";

export const dynamic = "force-dynamic";

export default async function PostfachPage() {
  const supabase = await createClient();

  // Kein manueller user_id-Filter nötig — RLS liefert ausschließlich eigene
  // Zeilen (siehe "Nutzer sieht eigene Notifications" in 20261201000001).
  const { data, error } = await supabase
    .from("organizer_notifications")
    .select("id, type, title, body, link_href, read_at, created_at")
    .order("created_at", { ascending: false })
    .limit(100)
    .returns<NotificationRow[]>();

  const notifications = data ?? [];
  const unread = notifications.filter((n) => !n.read_at);

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
            <CardContent className="pt-5 text-sm text-[#726c78]">
              Das Postfach ist nach der nächsten Datenbank-Aktualisierung verfügbar.
            </CardContent>
          </Card>
        )}

        {!error && notifications.length === 0 && (
          <Card>
            <CardContent className="pt-5 text-sm text-[#726c78]">
              Noch keine Benachrichtigungen — hier erscheinen z.B. Claim-Entscheidungen und Promotion-Freigaben.
            </CardContent>
          </Card>
        )}

        {!error && notifications.length > 0 && <NotificationList notifications={notifications} />}
      </PageBody>
    </div>
  );
}
