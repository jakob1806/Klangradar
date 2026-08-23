import { callAiFunction, hasAnyAiProviderConfigured, type AiFunctionDeclaration } from "../_shared/ai/router.ts";
import { assessEnsembleName } from "../_shared/entityNameValidation.ts";

const PARSE_PARTICIPANTS: AiFunctionDeclaration = {
  name: "parse_event_participants",
  description: "Erkennt ausschließlich auftretende Personen und Ensembles samt konkreter Veranstaltungsrolle.",
  parameters: {
    type: "object",
    properties: {
      participants: {
        type: "array",
        items: {
          type: "object",
          properties: {
            name: {
              type: "string",
              description: "Vollständiger Name der Person oder des Ensembles, ohne Rollenbezeichnung.",
            },
            entityType: {
              type: "string",
              enum: ["person", "ensemble"],
            },
            roleLabel: {
              type: "string",
              description:
                "Die konkrete Rolle exakt und knapp, z. B. Dirigent, Violine, Basssolist oder Lady Macbeth. Weglassen, wenn keine Rolle erkennbar ist.",
            },
            roleKind: {
              type: "string",
              enum: ["komponist", "dirigent", "solist", "chorleiter", "moderator"],
              description: "Optionale grobe Kategorie. Nur setzen, wenn zweifelsfrei passend.",
            },
          },
          required: ["name", "entityType"],
        },
      },
    },
    required: ["participants"],
  },
};

const jsonHeaders = { "content-type": "application/json; charset=utf-8" };

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Nur POST ist erlaubt." }), { status: 405, headers: jsonHeaders });
  }
  if (!hasAnyAiProviderConfigured()) {
    return new Response(
      JSON.stringify({ error: "Kein AI-Provider-Secret gesetzt (CEREBRAS_API_KEY, NVIDIA_API_KEY oder GEMINI_API_KEY)." }),
      { status: 500, headers: jsonHeaders },
    );
  }

  let body: { text?: unknown };
  try {
    body = await req.json();
  } catch {
    body = {};
  }
  const text = typeof body.text === "string" ? body.text.trim().slice(0, 20_000) : "";
  if (text.length < 3) {
    return new Response(JSON.stringify({ error: "Der eingefügte Text ist leer." }), { status: 400, headers: jsonHeaders });
  }

  const result = await callAiFunction(
    "Du extrahierst Besetzungslisten klassischer Konzerte und Opern. " +
      "Erfinde niemals Namen oder Rollen. Veranstalter, Agenturen, Spielstätten, Komponisten ohne tatsächliche Mitwirkung und Werktitel sind keine Mitwirkenden. " +
      "Bewahre konkrete Rollen wie 'Lady Macbeth', 'Basssolist', 'Sopran', 'Violine' oder 'Musikalische Leitung' als roleLabel. " +
      "Ein Orchester, Chor, Quartett oder sonstiger Gruppenname ist entityType ensemble. Einzelne Menschen sind person. " +
      "Doppelte Nennungen derselben Entität nur einmal ausgeben.",
    text,
    PARSE_PARTICIPANTS,
  );

  if (!result) {
    return new Response(JSON.stringify({ error: "Alle KI-Provider konnten den Text gerade nicht auswerten." }), {
      status: 502,
      headers: jsonHeaders,
    });
  }

  const raw = Array.isArray(result.args.participants) ? result.args.participants : [];
  const seen = new Set<string>();
  const participants = raw.flatMap((item: unknown) => {
    if (!item || typeof item !== "object") return [];
    const value = item as Record<string, unknown>;
    const name = typeof value.name === "string" ? value.name.trim() : "";
    const entityType = value.entityType === "ensemble" ? "ensemble" : value.entityType === "person" ? "person" : null;
    if (!name || !entityType) return [];
    if (entityType === "ensemble" && !assessEnsembleName(name).safe) return [];
    const key = `${entityType}:${name.toLocaleLowerCase("de")}`;
    if (seen.has(key)) return [];
    seen.add(key);
    const allowedKinds = new Set(["komponist", "dirigent", "solist", "chorleiter", "moderator"]);
    const roleKind = typeof value.roleKind === "string" && allowedKinds.has(value.roleKind) ? value.roleKind : null;
    const roleLabel = typeof value.roleLabel === "string" ? value.roleLabel.trim().slice(0, 160) || null : null;
    return [{ name, entityType, roleLabel, roleKind }];
  });

  return new Response(JSON.stringify({ participants, provider: result.provider }), { headers: jsonHeaders });
});
