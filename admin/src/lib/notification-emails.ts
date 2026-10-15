import { formatConcertDay, PLACEMENT_NAME, ENTITY_TYPE_NAME, portalEmail, type PortalEmail } from "@/lib/portal-email";

// Alle Benachrichtigungen rund um Promotionen und Claims an einer Stelle.

type PromotionInfo = { eventTitle: string; placement: string; concertAt: string | null; priceLabel?: string | null };

const placementName = (p: PromotionInfo) => PLACEMENT_NAME[p.placement] ?? p.placement;
const runsUntil = (p: PromotionInfo) => `Die Promotion läuft ab Zahlungseingang bis zum Konzerttag (${formatConcertDay(p.concertAt)}).`;

export function promotionRequestedEmail(p: PromotionInfo): PortalEmail {
  return portalEmail({
    subject: `Anfrage eingegangen: ${placementName(p)} für „${p.eventTitle}“`,
    eyebrow: "Promotion-Anfrage",
    title: "Danke, deine Anfrage ist eingegangen",
    paragraphs: [
      "Die Klangradar-Redaktion prüft deine Anfrage in der Regel innerhalb von 1–2 Werktagen. Sobald sie freigegeben ist, bekommst du eine E-Mail mit dem Zahlungslink.",
      runsUntil(p),
    ],
    facts: [["Event", p.eventTitle], ["Platzierung", placementName(p)], ...(p.priceLabel ? [["Preis", p.priceLabel] as [string, string]] : [])],
    cta: { label: "Anfrage ansehen", href: "/veranstalter/promote" },
    note: "Bis zur Zahlung kannst du die Anfrage jederzeit stornieren.",
  });
}

export function promotionRequestedRedaktionEmail(p: PromotionInfo & { requester: string }): PortalEmail {
  return portalEmail({
    subject: `Neue Promotion-Anfrage: ${placementName(p)} für „${p.eventTitle}“`,
    eyebrow: "Redaktion · Neue Anfrage",
    title: "Eine Promotion wartet auf Prüfung",
    paragraphs: [`${p.requester} möchte „${p.eventTitle}“ bewerben.`],
    facts: [["Event", p.eventTitle], ["Platzierung", placementName(p)], ["Konzerttag", formatConcertDay(p.concertAt)]],
    cta: { label: "Im Redaktions-Dashboard prüfen", href: "/event-promotions" },
    footer: "Interne Benachrichtigung der Klangradar-Redaktion.",
  });
}

export function promotionApprovedEmail(p: PromotionInfo & { reviewerNote?: string | null }): PortalEmail {
  return portalEmail({
    subject: `Freigegeben: ${placementName(p)} für „${p.eventTitle}“ – jetzt bezahlen`,
    eyebrow: "Promotion freigegeben",
    title: "Deine Promotion ist freigegeben",
    paragraphs: [
      "Schließe jetzt die Zahlung ab. Direkt danach wird dein Event in der Klangradar-App an der gebuchten Stelle angezeigt (klein als „Anzeige“ gekennzeichnet).",
      runsUntil(p),
      ...(p.reviewerNote ? [`Hinweis der Redaktion: ${p.reviewerNote}`] : []),
    ],
    facts: [["Event", p.eventTitle], ["Platzierung", placementName(p)], ...(p.priceLabel ? [["Preis", p.priceLabel] as [string, string]] : []), ["Läuft bis", formatConcertDay(p.concertAt)]],
    cta: { label: "Jetzt bezahlen", href: "/veranstalter/promote" },
    note: "Die Platzierung startet erst nach erfolgreicher Zahlung. Je früher du zahlst, desto länger läuft sie.",
  });
}

export function promotionRejectedEmail(p: PromotionInfo & { reviewerNote?: string | null }): PortalEmail {
  return portalEmail({
    subject: `Promotion für „${p.eventTitle}“ nicht freigegeben`,
    eyebrow: "Promotion-Anfrage",
    title: "Deine Anfrage wurde leider nicht freigegeben",
    paragraphs: [p.reviewerNote ? `Begründung der Redaktion: ${p.reviewerNote}` : "Die Redaktion hat deine Anfrage nicht freigegeben. Es wurde nichts berechnet.", "Du kannst jederzeit eine neue Anfrage stellen, z. B. mit einer anderen Platzierung."],
    facts: [["Event", p.eventTitle], ["Platzierung", placementName(p)]],
    cta: { label: "Zu Push & Promote", href: "/veranstalter/promote" },
  });
}

export function promotionActiveEmail(p: PromotionInfo & { amountLabel?: string | null; promotionId: string }): PortalEmail {
  return portalEmail({
    subject: `Live: „${p.eventTitle}“ wird jetzt beworben`,
    eyebrow: "Promotion aktiv",
    title: "Zahlung eingegangen – deine Promotion ist live",
    paragraphs: [
      `„${p.eventTitle}“ erscheint ab sofort als ${placementName(p)} in der Klangradar-App.`,
      `Die Promotion läuft bis zum Konzerttag (${formatConcertDay(p.concertAt)}). Unter Push & Promote siehst du laufend, wie viel zusätzliche Reichweite und Klicks sie bringt.`,
    ],
    facts: [["Event", p.eventTitle], ["Platzierung", placementName(p)], ...(p.amountLabel ? [["Bezahlt", p.amountLabel] as [string, string]] : []), ["Läuft bis", formatConcertDay(p.concertAt)]],
    cta: { label: "Statistik ansehen", href: "/veranstalter/promote" },
    note: `Die Rechnung kannst du unter Finanzen herunterladen.`,
  });
}

export function promotionPaymentReminderEmail(p: PromotionInfo): PortalEmail {
  return portalEmail({
    subject: `Erinnerung: Zahlung für „${p.eventTitle}“ noch offen`,
    eyebrow: "Erinnerung",
    title: "Deine Promotion wartet noch auf die Zahlung",
    paragraphs: [
      "Die Redaktion hat deine Promotion bereits vor einigen Tagen freigegeben. Sie startet, sobald die Zahlung eingegangen ist.",
      runsUntil(p),
      "Ohne Zahlung verfällt die Freigabe automatisch, sobald das Konzert beginnt.",
    ],
    facts: [["Event", p.eventTitle], ["Platzierung", placementName(p)], ...(p.priceLabel ? [["Preis", p.priceLabel] as [string, string]] : [])],
    cta: { label: "Jetzt bezahlen", href: "/veranstalter/promote" },
    note: "Kein Interesse mehr? Du kannst die Anfrage im Portal stornieren, dann erinnern wir dich nicht erneut.",
  });
}

export function promotionExpiredEmail(p: PromotionInfo): PortalEmail {
  return portalEmail({
    subject: `Promotion für „${p.eventTitle}“ verfallen`,
    eyebrow: "Promotion",
    title: "Die Freigabe ist verfallen",
    paragraphs: ["Das Konzert hat begonnen, ohne dass die Zahlung eingegangen ist. Die Anfrage wurde deshalb automatisch storniert – es wurde nichts berechnet."],
    facts: [["Event", p.eventTitle], ["Platzierung", placementName(p)]],
    cta: { label: "Neue Promotion anfragen", href: "/veranstalter/promote" },
  });
}

export function promotionSummaryEmail(p: PromotionInfo & { stats: { reachUplift: string; extraViews: number; clickUplift: string; extraClicks: number; impressions: number } }): PortalEmail {
  return portalEmail({
    subject: `Ergebnis deiner Promotion für „${p.eventTitle}“`,
    eyebrow: "Promotion abgeschlossen",
    title: "So hat deine Promotion gewirkt",
    paragraphs: [`Die Promotion für „${p.eventTitle}“ ist mit dem Konzerttag beendet. Hier das Ergebnis im Vergleich zu den Tagen davor:`],
    facts: [
      ["Reichweite", `${p.stats.reachUplift} (${signed(p.stats.extraViews)} Aufrufe)`],
      ["Ticket-Klicks", `${p.stats.clickUplift} (${signed(p.stats.extraClicks)} Klicks)`],
      ["Einblendungen im Feed", p.stats.impressions.toLocaleString("de-DE")],
    ],
    cta: { label: "Nächste Promotion planen", href: "/veranstalter/promote" },
  });
}

export function promotionReviewReminderRedaktionEmail(items: { eventTitle: string; placement: string; requestedAt: string }[]): PortalEmail {
  return portalEmail({
    subject: `${items.length} Promotion-Anfrage${items.length === 1 ? "" : "n"} seit über 3 Tagen offen`,
    eyebrow: "Redaktion · Erinnerung",
    title: "Diese Anfragen warten seit über 3 Tagen",
    paragraphs: items.map((i) => `${i.eventTitle} – ${PLACEMENT_NAME[i.placement] ?? i.placement} (seit ${new Date(i.requestedAt).toLocaleDateString("de-DE")})`),
    cta: { label: "Jetzt prüfen", href: "/event-promotions" },
    footer: "Interne Benachrichtigung der Klangradar-Redaktion.",
  });
}

type ClaimInfo = { entityType: string; entityName: string };
const entityLabel = (c: ClaimInfo) => `${ENTITY_TYPE_NAME[c.entityType] ?? "Profil"} „${c.entityName}“`;

export function claimRequestedEmail(c: ClaimInfo): PortalEmail {
  return portalEmail({
    subject: `Anfrage eingegangen: ${c.entityName}`,
    eyebrow: "Profil beanspruchen",
    title: "Danke, deine Anfrage ist eingegangen",
    paragraphs: [`Du möchtest ${entityLabel(c)} auf Klangradar verwalten. Die Redaktion prüft deinen Nachweis in der Regel innerhalb von 1–2 Werktagen und meldet sich per E-Mail.`],
    facts: [["Profil", c.entityName], ["Typ", ENTITY_TYPE_NAME[c.entityType] ?? c.entityType]],
    cta: { label: "Zum Veranstalterportal", href: "/veranstalter" },
  });
}

export function claimRequestedRedaktionEmail(c: ClaimInfo & { requester: string }): PortalEmail {
  return portalEmail({
    subject: `Neue Claim-Anfrage: ${c.entityName}`,
    eyebrow: "Redaktion · Neue Anfrage",
    title: "Ein Claim wartet auf Prüfung",
    paragraphs: [`${c.requester} möchte ${entityLabel(c)} verwalten.`],
    cta: { label: "Im Redaktions-Dashboard prüfen", href: "/entity-claims" },
    footer: "Interne Benachrichtigung der Klangradar-Redaktion.",
  });
}

export function claimDecisionEmail(c: ClaimInfo & { outcome: "approved" | "rejected" }): PortalEmail {
  return c.outcome === "approved"
    ? portalEmail({
        subject: `Genehmigt: Du verwaltest jetzt ${c.entityName}`,
        eyebrow: "Claim genehmigt",
        title: `Willkommen – ${c.entityName} gehört jetzt zu deinem Portal`,
        paragraphs: [`Dein Antrag für ${entityLabel(c)} wurde genehmigt. Du kannst jetzt Profil und Events pflegen, Team-Mitglieder einladen und Promotionen buchen.`],
        cta: { label: "Jetzt loslegen", href: "/veranstalter" },
      })
    : portalEmail({
        subject: `Claim für ${c.entityName} nicht genehmigt`,
        eyebrow: "Claim",
        title: "Dein Antrag wurde leider nicht genehmigt",
        paragraphs: [`Wir konnten deine Berechtigung für ${entityLabel(c)} nicht bestätigen. Bei Fragen antworte einfach auf diese E-Mail.`],
        cta: { label: "Zum Veranstalterportal", href: "/veranstalter" },
      });
}

export function claimReviewReminderRedaktionEmail(items: { entityName: string; entityType: string; createdAt: string }[]): PortalEmail {
  return portalEmail({
    subject: `${items.length} Claim-Anfrage${items.length === 1 ? "" : "n"} seit über 3 Tagen offen`,
    eyebrow: "Redaktion · Erinnerung",
    title: "Diese Claims warten seit über 3 Tagen",
    paragraphs: items.map((i) => `${i.entityName} (${ENTITY_TYPE_NAME[i.entityType] ?? i.entityType}, seit ${new Date(i.createdAt).toLocaleDateString("de-DE")})`),
    cta: { label: "Jetzt prüfen", href: "/entity-claims" },
    footer: "Interne Benachrichtigung der Klangradar-Redaktion.",
  });
}

function signed(value: number) {
  return `${value >= 0 ? "+" : "−"}${Math.abs(Math.round(value)).toLocaleString("de-DE")}`;
}
