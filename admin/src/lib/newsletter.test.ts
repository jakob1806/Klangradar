import { describe, expect, it, vi } from "vitest";
vi.mock("@/lib/supabase/admin", () => ({ createAdminClient: () => ({}) }));
vi.mock("@/lib/resend", () => ({ getResend: () => ({}) }));
import { followedNewEventsEmail, isoWeekKey, weeklyDigestEmail } from "./newsletter";

const recipient = { user_id: "u", email: "a@b.de", display_name: "Anna Muster", city_id: null, city_name: "München", unsubscribe_token: "11111111-2222-3333-4444-555555555555" };
const pick = (reason: string, title: string) => ({ event_id: title, slug: title.toLowerCase(), title, start_datetime: "2026-10-30T19:30:00Z", venue_name: "Isarphilharmonie", image_url: null, reason, reason_detail: `Grund ${reason}`, score: 5 });

describe("newsletter", () => {
  it("ISO-Woche", () => {
    expect(isoWeekKey(new Date("2026-10-22T12:00:00Z"))).toBe("2026-W43");
    expect(isoWeekKey(new Date("2027-01-01T12:00:00Z"))).toBe("2026-W53");
  });

  it("Wochenmail: persönlich, nach Rubriken, mit Abmeldelink", () => {
    const mail = weeklyDigestEmail(recipient, [pick("followed", "Mahler 2"), pick("saved", "Liederabend"), pick("taste", "Bach")]);
    expect(mail.subject).toBe("Mahler 2 und 2 weitere Konzerte für dich");
    expect(mail.html).toContain("Guten Morgen, Anna.");
    expect(mail.html).toContain("Diese Woche in München");
    expect(mail.html).toContain("/email/klangradar-logo.png");
    expect(mail.html).toContain("https://klangradar.com/e/mahler%202");
    expect(mail.unsubscribeUrl).toContain("kind=weekly_digest");
    expect(mail.text).toContain("Abmelden:");
  });

  it("Gefolgte-Mail nennt die Gefolgten", () => {
    const mail = followedNewEventsEmail(recipient, [{ event_id: "1", slug: "a", title: "Neu A", start_datetime: "2026-11-02T19:00:00Z", venue_name: null, image_url: null, followed_name: "BRSO" }]);
    expect(mail.subject).toBe("Neu: Neu A");
    expect(mail.html).toContain("Neue Termine von BRSO");
  });

  it("escaped Titel", () => {
    expect(weeklyDigestEmail(recipient, [pick("taste", "<b>X</b>"), pick("taste", "Y")]).html).not.toContain("<b>X</b>");
  });
});
