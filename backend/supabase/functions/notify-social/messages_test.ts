import { assertEquals } from "jsr:@std/assert@1";
import { socialMessage } from "./messages.ts";

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
