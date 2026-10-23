import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { detectTitleStatus } from "./cancellation.ts";

Deno.test("erkennt ABGESAGT-Präfix (Laeiszhalle-Beispiel)", () => {
  assertEquals(detectTitleStatus("ABGESAGT: Julia Kleiter / Julian Prégardien / Sir András Schiff"), "cancelled");
});

Deno.test("erkennt weitere Schreibweisen als abgesagt", () => {
  for (const t of ["Abgesagt – Kammerkonzert", "[Abgesagt] Liederabend", "(entfällt) Orgelkonzert", "CANCELLED: Gala", "Konzert (ABGESAGT)", "Sinfoniekonzert - abgesagt"]) {
    assertEquals(detectTitleStatus(t), "cancelled", t);
  }
});

Deno.test("erkennt Verschiebung", () => {
  assertEquals(detectTitleStatus("VERSCHOBEN: Klavierabend"), "postponed");
});

Deno.test("lässt normale Titel unberührt, auch bei ähnlichen Wörtern", () => {
  for (const t of ["Die abgesagte Oper – ein Hörspiel", "Entfesselt: Beethoven", "Verschobene Perspektiven", "Mozart: Requiem"]) {
    assertEquals(detectTitleStatus(t), null, t);
  }
});

import { detectEventStatus, detectTextStatus } from "./cancellation.ts";

Deno.test("Beschreibung: Absage erkannt", () => {
  assertEquals(detectTextStatus("Das Konzert muss leider krankheitsbedingt abgesagt werden."), "cancelled");
  assertEquals(detectTextStatus("Die Veranstaltung entfällt."), "cancelled");
  assertEquals(detectTextStatus("Dieser Termin findet leider nicht statt."), "cancelled");
  assertEquals(detectTextStatus("This concert has been cancelled."), "cancelled");
});

Deno.test("Beschreibung: Verschiebung erkannt", () => {
  assertEquals(detectTextStatus("Das Konzert wird auf den 12. März verschoben."), "postponed");
});

Deno.test("Beschreibung: Hinweise lösen nichts aus", () => {
  assertEquals(detectTextStatus("Bei Absage durch den Veranstalter erstatten wir den Kartenpreis."), null);
  assertEquals(detectTextStatus("Ein Abend mit Liedern über Abschied und Verlust."), null);
  assertEquals(detectTextStatus(null), null);
});

Deno.test("Titel hat Vorrang", () => {
  assertEquals(detectEventStatus("ABGESAGT: Liederabend", "Das Konzert wird verschoben."), "cancelled");
  assertEquals(detectEventStatus("Liederabend", "Die Vorstellung fällt aus."), "cancelled");
});
