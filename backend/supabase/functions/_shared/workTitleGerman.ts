// Erstellt von Claude Code (24.10.2026): englische Werktitel (mphil.de/en,
// andere englische Quellen) in die übliche deutsche Form bringen, damit sie
// vorhandene deutsche Werke treffen statt Mischtitel wie "Konzert for Violin"
// anzulegen. Nur verbreitete Muster – Eigennamen/Zitate in »…« bleiben.

const INSTRUMENTS: [RegExp, string][] = [
  [/\bviolin(s)?\b/gi, "Violine"], [/\bviolas?\b/gi, "Viola"], [/\b(violon)?cello\b/gi, "Violoncello"],
  [/\bdouble bass\b/gi, "Kontrabass"], [/\bpiano\b/gi, "Klavier"], [/\bharp\b/gi, "Harfe"],
  [/\bflute\b/gi, "Flöte"], [/\boboe\b/gi, "Oboe"], [/\bclarinet\b/gi, "Klarinette"], [/\bbassoon\b/gi, "Fagott"],
  [/\bhorn\b/gi, "Horn"], [/\btrumpet\b/gi, "Trompete"], [/\btrombone\b/gi, "Posaune"], [/\borgan\b/gi, "Orgel"],
  [/\bsoprano\b/gi, "Sopran"], [/\bchoir\b/gi, "Chor"], [/\bstrings\b/gi, "Streicher"],
  [/\b(small |chamber )?orchestra\b/gi, "Orchester"], [/\bleft hand\b/gi, "linke Hand"],
];

function key(letter: string, accidental: string | undefined, mode: string): string {
  let name = letter.toUpperCase();
  const acc = (accidental ?? "").toLowerCase();
  if (acc.includes("flat")) name = name === "B" ? "B" : name === "E" || name === "A" ? name + "s" : name + "es";
  else if (acc.includes("sharp")) name += "is";
  else if (name === "B") name = "H";
  return /minor/i.test(mode) ? `${name.toLowerCase()}-Moll` : `${name}-Dur`;
}

export function germanizeWorkTitle(title: string): string {
  let t = title.replace(/\s+/g, " ").trim();
  if (!/[A-Za-z]/.test(t) || /\b(für|Sinfonie|Konzert für)\b/.test(t)) return t;
  t = t.replace(/\b([A-H])(?:[- ](flat|sharp))? (major|minor)\b/gi, (_m, l, a, mode) => key(l, a, mode));
  t = t.replace(/\bin ([a-hA-H](?:is|es|s)?-(?:Dur|Moll))\b/g, "$1");
  t = t.replace(/\bConcerto\b/gi, "Konzert").replace(/\bSymphony\b/gi, "Sinfonie").replace(/\bSymphonie\b/g, "Sinfonie");
  t = t.replace(/\bOverture to\b/gi, "Ouvertüre zu").replace(/\bOverture\b/gi, "Ouvertüre");
  t = t.replace(/\bSymphonic Dances\b/gi, "Sinfonische Tänze").replace(/\bSymphonic Movements from\b/gi, "Sinfonische Sätze aus");
  t = t.replace(/\bSymphonic Interlude from the Opera\b/gi, "Sinfonisches Zwischenspiel aus der Oper");
  t = t.replace(/\bSuite from\b/gi, "Suite aus").replace(/\bfrom the opera\b/gi, "aus der Oper");
  t = t.replace(/\bOrchestrated by\b/gi, "orchestriert von").replace(/\bfor\b/gi, "für").replace(/\band\b/gi, "und");
  t = t.replace(/\bNo\.\s*/gi, "Nr. ").replace(/\bOpus\s*/gi, "op. ").replace(/\bOp\.\s*/g, "op. ");
  for (const [pattern, replacement] of INSTRUMENTS) t = t.replace(pattern, replacement);
  return t.replace(/\s+,/g, ",").replace(/\s+/g, " ").trim();
}
