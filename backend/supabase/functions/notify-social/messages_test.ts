import { assertEquals } from "jsr:@std/assert@1";
import { socialMessage, socialPushData } from "./messages.ts";

Deno.test("plan_invite nennt Einladende:n und Konzert", () => {
  const msg = socialMessage({ kind: "plan_invite", actorName: "Anna", eventTitle: "Mahler 2" });
  assertEquals(msg?.title, "Anna lädt dich ein");
  assertEquals(msg?.body, "Kommst du mit zu „Mahler 2“?");
});

Deno.test("friend_also_attending verlinkt das Konzert", () => {
  assertEquals(socialMessage({ kind: "friend_also_attending", actorName: "Tom", eventTitle: "Liederabend", eventSlug: "liederabend" })?.route, "/event/liederabend");
});

Deno.test("unbekannte Art liefert null", () => {
  assertEquals(socialMessage({ kind: "x", actorName: "A" }), null);
});

Deno.test("Social-Ausbau: neue Mitteilungen", () => {
  assertEquals(socialMessage({ kind: "joins_you", actorName: "Lena", eventTitle: "Mahler 2" })?.title, "Lena kommt mit");
  assertEquals(socialMessage({ kind: "rating_applause", actorName: "Lena", eventTitle: "Mahler 2" })?.route, "/friends");
  assertEquals(socialMessage({ kind: "rating_comment", actorName: "Lena" })?.body, "Zu deiner Bewertung von ein Konzert.");
  assertEquals(socialMessage({ kind: "group_added", actorName: "Lena" })?.title, "Neue Gruppe");
});

Deno.test("Freunde-Ausbau: Anfrage mit Schnellaktionen und Absender", () => {
  assertEquals(socialMessage({ kind: "friend_request", actorName: "Lena" })?.category, "FRIEND_REQUEST");
  assertEquals(socialMessage({ kind: "friend_accepted", actorName: "Lena" })?.category, undefined);
  assertEquals(socialPushData("friend_request", "/friends", "abc"), { route: "/friends", kind: "friend_request", actor_id: "abc" });
  assertEquals(socialPushData("group_added", "/friends", null), { route: "/friends", kind: "group_added" });
});

Deno.test("Freunde-Ausbau: Einladung und Ticket übrig", () => {
  assertEquals(socialMessage({ kind: "invite_accepted", actorName: "Lena" })?.body, "Lena ist deiner Einladung gefolgt. Ihr seid jetzt verbunden.");
  const offered = socialMessage({ kind: "ticket_offered", actorName: "Lena", eventTitle: "Mahler 2", eventSlug: "mahler-2" });
  assertEquals(offered?.title, "Ticket übrig");
  assertEquals(offered?.route, "/event/mahler-2");
  assertEquals(socialMessage({ kind: "ticket_claimed", actorName: "Tom", eventTitle: "Mahler 2" })?.body, "Tom nimmt dein Ticket für „Mahler 2“.");
});
