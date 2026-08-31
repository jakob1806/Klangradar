import Link from "next/link";
import { Bell } from "lucide-react";
import { createClient } from "@/lib/supabase/server";

// Eigene kleine Server-Komponente statt Prop-Drilling aus dem Layout — hält
// den Ungelesen-Count serverseitig aktuell (kein Client-Poll nötig) und
// bleibt harmlos, falls organizer_notifications in einer Umgebung noch
// nicht migriert ist (gleiche Nachsichtigkeit wie finanzen/page.tsx).
export async function NotificationBell() {
  const supabase = await createClient();
  const { count } = await supabase
    .from("organizer_notifications")
    .select("id", { count: "exact", head: true })
    .is("read_at", null);

  const unread = count ?? 0;

  return (
    <Link
      href="/veranstalter/postfach"
      className="relative flex size-9 items-center justify-center rounded-full text-[#4a4550] transition hover:bg-black/[0.05] hover:text-[#15131a]"
      aria-label={unread > 0 ? `Postfach, ${unread} ungelesen` : "Postfach"}
    >
      <Bell className="size-[18px]" />
      {unread > 0 && (
        <span className="absolute right-1 top-1 flex size-[15px] items-center justify-center rounded-full bg-[#b3273e] text-[9px] font-bold text-white">
          {unread > 9 ? "9+" : unread}
        </span>
      )}
    </Link>
  );
}
