import { createClient } from "@/lib/supabase/server";
import { PageHeader, PageBody } from "@/components/organizer/page-header";
import { Card, CardContent } from "@/components/organizer/ui/card";
import { Badge } from "@/components/organizer/ui/badge";
import { Button } from "@/components/organizer/ui/button";
import { markNotificationReadAndGo, markAllNotificationsRead } from "./actions";

export const dynamic = "force-dynamic";

type NotificationRow = {
  id: string;
  type: string;
  title: string;
  body: string | null;
  link_href: string | null;
  read_at: string | null;
  created_at: string;
};

const dateFormatter = new Intl.DateTimeFormat("de-DE", { day: "2-digit", month: "short", hour: "2-digit", minute: "2-digit" });

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

      <div className="flex flex-col gap-2">
        {notifications.map((notification) => (
          <form
            key={notification.id}
            action={markNotificationReadAndGo.bind(null, notification.id, notification.link_href ?? "/veranstalter")}
          >
            <button type="submit" className="w-full text-left">
              <Card className={notification.read_at ? "opacity-70" : "border-[#2D2A6E]/25 bg-[#2D2A6E]/[0.03]"}>
                <CardContent className="flex items-start justify-between gap-4 pt-5">
                  <div className="flex flex-col gap-1">
                    <div className="flex items-center gap-2">
                      {!notification.read_at && <Badge variant="accent">Neu</Badge>}
                      <span className="text-sm font-semibold text-[#15131a]">{notification.title}</span>
                    </div>
                    {notification.body && <p className="text-[13px] text-[#4a4550]">{notification.body}</p>}
                  </div>
                  <span className="shrink-0 text-xs text-[#726c78]">{dateFormatter.format(new Date(notification.created_at))}</span>
                </CardContent>
              </Card>
            </button>
          </form>
        ))}
      </div>
      </PageBody>
    </div>
  );
}
