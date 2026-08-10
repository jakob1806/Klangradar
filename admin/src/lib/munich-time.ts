export const MUNICH_TIME_ZONE = "Europe/Berlin";

type LocalParts = {
  year: number;
  month: number;
  day: number;
  hour: number;
  minute: number;
};

function parseLocalInput(value: string): LocalParts {
  const match = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})$/.exec(value);
  if (!match) throw new Error("Ungültiges Datum/Uhrzeit-Format.");
  return {
    year: Number(match[1]),
    month: Number(match[2]),
    day: Number(match[3]),
    hour: Number(match[4]),
    minute: Number(match[5]),
  };
}

function partsInMunich(date: Date): LocalParts {
  const values = Object.fromEntries(
    new Intl.DateTimeFormat("en-CA", {
      timeZone: MUNICH_TIME_ZONE,
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
      hour: "2-digit",
      minute: "2-digit",
      hourCycle: "h23",
    }).formatToParts(date).map((part) => [part.type, part.value]),
  );
  return {
    year: Number(values.year),
    month: Number(values.month),
    day: Number(values.day),
    hour: Number(values.hour),
    minute: Number(values.minute),
  };
}

function utcMillis(parts: LocalParts): number {
  return Date.UTC(parts.year, parts.month - 1, parts.day, parts.hour, parts.minute);
}

/** Wandelt den zeitzonenlosen Wert eines datetime-local-Felds ausdrücklich
 * aus Europe/Berlin nach UTC. Funktioniert identisch auf Vercel (UTC) und
 * lokal und berücksichtigt Sommer-/Winterzeit. */
export function munichLocalToISOString(value: string): string {
  const wanted = parseLocalInput(value);
  const naiveUTC = utcMillis(wanted);
  let result = naiveUTC;

  // Zweimalige Offset-Korrektur deckt auch den Wechsel zwischen CET/CEST ab.
  for (let attempt = 0; attempt < 2; attempt += 1) {
    const shown = partsInMunich(new Date(result));
    result += naiveUTC - utcMillis(shown);
  }

  const verified = partsInMunich(new Date(result));
  if (utcMillis(verified) !== naiveUTC) {
    throw new Error("Diese Uhrzeit existiert wegen der Zeitumstellung in München nicht.");
  }
  return new Date(result).toISOString();
}

export function toMunichDatetimeLocal(iso: string | null): string {
  if (!iso) return "";
  const parts = partsInMunich(new Date(iso));
  const pad = (value: number) => String(value).padStart(2, "0");
  return `${parts.year}-${pad(parts.month)}-${pad(parts.day)}T${pad(parts.hour)}:${pad(parts.minute)}`;
}

export function formatMunichDateTime(
  iso: string,
  options: Intl.DateTimeFormatOptions = { dateStyle: "medium", timeStyle: "short" },
): string {
  return new Intl.DateTimeFormat("de-DE", { ...options, timeZone: MUNICH_TIME_ZONE }).format(new Date(iso));
}
