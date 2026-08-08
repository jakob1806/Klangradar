export type PortalAccessMode = "account" | "password" | null;

export function normalizeEmail(value: string): string {
  return value.trim().toLocaleLowerCase("en-US");
}

export function parseEmailAllowlist(value: string): Set<string> {
  return new Set(value.split(",").map(normalizeEmail).filter(Boolean));
}

export function resolvePortalAccess({
  authenticatedEmail,
  passwordlessEmails,
  submittedPassword,
  expectedPassword,
}: {
  authenticatedEmail: string | null;
  passwordlessEmails: ReadonlySet<string>;
  submittedPassword: string;
  expectedPassword: string;
}): PortalAccessMode {
  if (
    authenticatedEmail !== null &&
    passwordlessEmails.has(normalizeEmail(authenticatedEmail))
  ) {
    return "account";
  }

  // Timing-sicherer Vergleich statt "===" — verhindert, dass die Laufzeit
  // des Vergleichs selbst Rückschlüsse auf einzelne Passwort-Zeichen zulässt.
  if (
    submittedPassword.length > 0 &&
    timingSafeEqual(submittedPassword, expectedPassword)
  ) {
    return "password";
  }

  return null;
}

export function timingSafeEqual(a: string, b: string): boolean {
  const aBytes = new TextEncoder().encode(a);
  const bBytes = new TextEncoder().encode(b);
  // Läuft bewusst über die längere der beiden Längen weiter (statt bei
  // Längen-Mismatch sofort false zurückzugeben) — sonst würde allein die
  // Antwortzeit schon die korrekte Passwortlänge verraten.
  const maxLength = Math.max(aBytes.length, bBytes.length);
  let diff = aBytes.length === bBytes.length ? 0 : 1;
  for (let i = 0; i < maxLength; i++) {
    diff |= (aBytes[i] ?? 0) ^ (bBytes[i] ?? 0);
  }
  return diff === 0;
}
