// Texte der Social-Pushes (notify-social). Eigene Datei für Tests.
export interface SocialItem {
  kind: string;
  actorName: string;
  eventTitle?: string | null;
  eventSlug?: string | null;
  listName?: string | null;
}

export interface SocialMessage {
  title: string;
  body: string;
  route: string;
  /** iOS-Kategorie mit Schnellaktionen (FRIEND_REQUEST: Annehmen/Ablehnen). */
  category?: string;
}

const quote = (s?: string | null) => (s ? `„${s}“` : "ein Konzert");

export function socialMessage(item: SocialItem): SocialMessage | null {
  const who = item.actorName || "Jemand";
  const eventRoute = item.eventSlug ? `/event/${item.eventSlug}` : "/friends";
  switch (item.kind) {
    case "friend_request":
      return { title: "Neue Freundschaftsanfrage", body: `${who} möchte sich mit dir auf Klangradar vernetzen.`, route: "/friends", category: "FRIEND_REQUEST" };
    case "friend_accepted":
      return { title: "Ihr seid jetzt befreundet", body: `${who} hat deine Anfrage angenommen.`, route: "/friends" };
    case "plan_invite":
      return { title: `${who} lädt dich ein`, body: `Kommst du mit zu ${quote(item.eventTitle)}?`, route: "/plans" };
    case "plan_going":
      return { title: "Zusage", body: `${who} kommt mit zu ${quote(item.eventTitle)}.`, route: "/plans" };
    case "plan_maybe":
      return { title: "Vielleicht", body: `${who} überlegt noch, ob es ${quote(item.eventTitle)} wird.`, route: "/plans" };
    case "plan_declined":
      return { title: "Absage", body: `${who} kann bei ${quote(item.eventTitle)} leider nicht.`, route: "/plans" };
    case "list_shared":
      return { title: "Geteilte Liste", body: `${who} hat die Liste ${quote(item.listName)} mit dir geteilt.`, route: "/friends" };
    case "friend_also_attending":
      return { title: "Ihr seid zusammen dort", body: `${who} geht auch zu ${quote(item.eventTitle)}.`, route: eventRoute };
    // Social-Ausbau 28.10.2026
    case "joins_you":
      return { title: `${who} kommt mit`, body: `${who} geht mit dir zu ${quote(item.eventTitle)}.`, route: "/plans" };
    case "rating_applause":
      return { title: "Applaus", body: `${who} applaudiert deiner Bewertung von ${quote(item.eventTitle)}.`, route: "/friends" };
    case "rating_comment":
      return { title: `${who} hat kommentiert`, body: `Zu deiner Bewertung von ${quote(item.eventTitle)}.`, route: "/friends" };
    case "group_added":
      return { title: "Neue Gruppe", body: `${who} hat dich zu einer Gruppe hinzugefügt.`, route: "/friends" };
    // Freunde-Ausbau 28.10.2026
    case "invite_accepted":
      return { title: "Einladung angenommen", body: `${who} ist deiner Einladung gefolgt. Ihr seid jetzt verbunden.`, route: "/friends" };
    case "ticket_offered":
      return { title: "Ticket übrig", body: `${who} hat ein Ticket für ${quote(item.eventTitle)} übrig. Wer zuerst zusagt, bekommt es.`, route: eventRoute };
    case "ticket_claimed":
      return { title: "Ticket vergeben", body: `${who} nimmt dein Ticket für ${quote(item.eventTitle)}.`, route: eventRoute };
    default:
      return null;
  }
}

/** Daten im Push: Route zum Öffnen, Art und Absender (für Schnellaktionen). */
export function socialPushData(kind: string, route: string, actorId?: string | null): Record<string, string> {
  return { route, kind, ...(actorId ? { actor_id: actorId } : {}) };
}
