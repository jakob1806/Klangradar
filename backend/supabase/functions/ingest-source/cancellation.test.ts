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
