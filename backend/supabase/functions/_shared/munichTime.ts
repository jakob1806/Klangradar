export const MUNICH_TIME_ZONE = "Europe/Berlin";

type Parts = {
  year: number;
  month: number;
  day: number;
  hour: number;
  minute: number;
};

function partsInMunich(date: Date): Parts {
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

function asUtc(parts: Parts): number {
  return Date.UTC(
    parts.year,
    parts.month - 1,
    parts.day,
    parts.hour,
    parts.minute,
  );
}

/** Interpretiert lokale Münchner Datumsteile DST-sicher als UTC-Zeitpunkt. */
export function munichLocalToDate(parts: Parts): Date {
  const wanted = asUtc(parts);
  let result = wanted;
  for (let attempt = 0; attempt < 2; attempt += 1) {
    result += wanted - asUtc(partsInMunich(new Date(result)));
  }
  return new Date(result);
}

/** UTC-Grenzen eines Münchner Kalendertags relativ zum übergebenen Zeitpunkt. */
export function munichDayRange(
  dayOffset: number,
  now = new Date(),
): { start: Date; end: Date } {
  const local = partsInMunich(now);
  const target = new Date(
    Date.UTC(local.year, local.month - 1, local.day + dayOffset),
  );
  const date = {
    year: target.getUTCFullYear(),
    month: target.getUTCMonth() + 1,
    day: target.getUTCDate(),
  };
  const start = munichLocalToDate({ ...date, hour: 0, minute: 0 });
  const next = new Date(Date.UTC(date.year, date.month - 1, date.day + 1));
  const endExclusive = munichLocalToDate({
    year: next.getUTCFullYear(),
    month: next.getUTCMonth() + 1,
    day: next.getUTCDate(),
    hour: 0,
    minute: 0,
  });
  return { start, end: new Date(endExclusive.getTime() - 1) };
}
