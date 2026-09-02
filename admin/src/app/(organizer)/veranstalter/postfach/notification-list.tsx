"use client";

import { useMemo, useState } from "react";
import { Card, CardContent } from "@/components/organizer/ui/card";
import { Badge } from "@/components/organizer/ui/badge";
import { markNotificationReadAndGo } from "./actions";

export interface NotificationRow {
  id: string;
  type: string;
  title: string;
  body: string | null;
  link_href: string | null;
  read_at: string | null;
  created_at: string;
}

const dateFormatter = new Intl.DateTimeFormat("de-DE", { day: "2-digit", month: "short", hour: "2-digit", minute: "2-digit" });

const TYPE_LABEL: Record<string, string> = {
  claim_decision: "Beanspruchung",
  promotion_approved: "Promotion",
  promotion_rejected: "Promotion",
  team_invite: "Team",
};

// Nutzerfeedback: bei bis zu 100 Einträgen war kein Filter nach Typ oder
// Lesestatus möglich -- Ungelesen/Typ-Filter analog zum Status-Filter der
// Events-Liste.
export function NotificationList({ notifications }: { notifications: NotificationRow[] }) {
  const [onlyUnread, setOnlyUnread] = useState(false);
  const [type, setType] = useState("all");

  const types = useMemo(() => [...new Set(notifications.map((n) => n.type))], [notifications]);
  const filtered = notifications.filter((n) => {
    if (onlyUnread && n.read_at) return false;
    if (type !== "all" && n.type !== type) return false;
    return true;
  });

  return (
    <div className="flex flex-col gap-4">
      {notifications.length > 0 && (
        <div className="flex flex-wrap items-center gap-2">
          <button
            type="button"
            onClick={() => setOnlyUnread((v) => !v)}
            className={`h-8 rounded-full border px-3 text-xs font-semibold transition ${
              onlyUnread ? "border-[#2D2A6E] bg-[#ECEBFA] text-[#2D2A6E]" : "border-black/10 bg-white text-[#4a4550] hover:bg-[#F5F5F1]"
            }`}
          >
            Nur ungelesen
          </button>
          {types.length > 1 && (
            <select
              value={type}
              onChange={(e) => setType(e.target.value)}
              className="h-8 rounded-full border border-black/10 bg-white px-3 text-xs font-semibold text-[#4a4550] focus-visible:border-[#2D2A6E] focus-visible:outline-none"
            >
              <option value="all">Alle Typen</option>
              {types.map((t) => (
                <option key={t} value={t}>
                  {TYPE_LABEL[t] ?? t}
                </option>
              ))}
            </select>
          )}
        </div>
      )}

      {notifications.length > 0 && filtered.length === 0 && (
        <p className="py-6 text-sm text-[#726c78]">Keine Benachrichtigungen für diesen Filter.</p>
      )}

      <div className="flex flex-col gap-2">
        {filtered.map((notification) => (
          <form key={notification.id} action={markNotificationReadAndGo.bind(null, notification.id, notification.link_href ?? "/veranstalter")}>
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
    </div>
  );
}
