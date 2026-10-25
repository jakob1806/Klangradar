// Erstellt von Claude Code (25.10.2026, Nutzermeldung "bei der Oper werden
// die Ticketpreise im Programm angezeigt"): Preisangaben aus Beschreibungs-
// texten lösen. staatsoper.de liefert z. B. "… Riccardo Drigo Preise H ,
// € 88 / 77 / 63 / 50 / 35 / 23 / 11 / 8 Abo-Geschenk-Abo IV" als Text.
export interface PriceSplit {
  description: string | null;
  priceMin: number | null;
  priceMax: number | null;
}

const PRICE_BLOCK = /\s*(?:Preise?\s+[A-Z]{0,3}\s*,?\s*)?€\s*(?:[\d.,]+|-)(?:\s*\/\s*(?:[\d.,]+|-))+(?:\s*<\s*30)?(?:\s+Abo[\w-]*(?:\s+[\w-]+){0,3})?/g;

export function splitPriceInfo(text: string | null): PriceSplit {
  if (!text) return { description: text, priceMin: null, priceMax: null };
  const values: number[] = [];
  const description = text.replace(PRICE_BLOCK, (block) => {
    for (const m of block.matchAll(/(\d+(?:[.,]\d{1,2})?)/g)) {
      const n = Number(m[1].replace(",", "."));
      if (n > 0 && n < 1000 && !/<\s*30/.test(block.slice(Math.max(0, (m.index ?? 0) - 3), (m.index ?? 0) + 4))) values.push(n);
    }
    return " ";
  }).replace(/\s*\bPreise?\s+[A-Z]{1,3}\s*,?\s*$/, "").replace(/\s{2,}/g, " ").trim();
  return {
    description: description.length ? description : null,
    priceMin: values.length ? Math.min(...values) : null,
    priceMax: values.length ? Math.max(...values) : null,
  };
}
