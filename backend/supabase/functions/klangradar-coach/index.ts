import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { callAiFunctionPreferGemini, type AiFunctionDeclaration } from "../_shared/ai/router.ts";

type Json = Record<string, unknown>;
type Filters = { date_from?: string; date_to?: string; max_budget?: number; city?: string; query?: string; exclude_opera?: boolean };

const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, apikey, content-type", "Content-Type": "application/json" };
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: cors });
const bearer = (req: Request) => req.headers.get("Authorization")?.replace(/^Bearer\s+/i, "") ?? "";

const PLAN_FUNCTION: AiFunctionDeclaration = {
  name: "plan_coach_response",
  description: "Erkennt die Absicht und extrahiert nur ausdrücklich genannte Suchfilter oder Memory-/Zielvorschläge.",
  parameters: {
    type: "object",
    properties: {
      intent: { type: "string", enum: ["explain_profile", "find_events", "plan_evening", "behavior_trend", "knowledge", "remember", "set_goal", "general"] },
      shouldSearchEvents: { type: "boolean" },
      filtersJson: { type: "string", description: "JSON mit optional date_from,date_to,max_budget,city,query,exclude_opera" },
      memoryProposalJson: { type: "string", description: "Nur bei ausdrücklichem 'merk dir': JSON mit category,label,value; sonst leerer String" },
      goalProposalJson: { type: "string", description: "Nur bei ausdrücklichem Ziel: JSON mit kind,title,target_value,period,metadata; sonst leerer String" },
    },
    required: ["intent", "shouldSearchEvents", "filtersJson", "memoryProposalJson", "goalProposalJson"],
  },
};

const ANSWER_FUNCTION: AiFunctionDeclaration = {
  name: "write_coach_answer",
  description: "Schreibt eine kurze persönliche Antwort der Klangradar KI ausschließlich aus dem gelieferten Kontext und den echten Treffern.",
  parameters: {
    type: "object",
    properties: {
      answer: { type: "string", description: "Deutsch, 2-3 kurze Absätze. Erst Erkenntnis, dann konkrete Empfehlung. Unsicherheit offen nennen." },
      suggestedPrompts: { type: "array", items: { type: "string" } },
    },
    required: ["answer", "suggestedPrompts"],
  },
};

function dateRange(date: Date) {
  const from = new Date(date); from.setHours(0, 0, 0, 0);
  const to = new Date(from); to.setDate(to.getDate() + 1);
  return { date_from: from.toISOString(), date_to: to.toISOString() };
}

// Nutzerfeedback: "diesen Monat"/"nächsten Monat" wurde bislang gar nicht
// erkannt -- ohne date_from/date_to griff der 90-Tage-Standardzeitraum der
// RPC, was zwar nicht zu leeren Ergebnissen führt, aber Monatsanfragen nicht
// wie erwartet eingrenzt.
function monthRange(monthsFromNow: number) {
  const from = new Date();
  from.setDate(1); from.setHours(0, 0, 0, 0);
  from.setMonth(from.getMonth() + monthsFromNow);
  const to = new Date(from);
  to.setMonth(to.getMonth() + 1);
  return { date_from: from.toISOString(), date_to: to.toISOString() };
}

const KNOWN_CITIES = ["München", "Berlin", "Hamburg", "Frankfurt", "Wien"];

// Einzige Quelle für "welche Stadt steht ausdrücklich im Text" -- wird sowohl
// vom lokalen Fallback-Planer als auch danach erneut auf das Ergebnis des
// KI-Planers angewendet (siehe unten), damit ein von der KI selbst
// geratener Stadtname den korrekten Default niemals stillschweigend
// überschreiben kann.
function explicitCityIn(message: string): string | undefined {
  const q = message.toLocaleLowerCase("de-DE");
  return KNOWN_CITIES.find((c) => q.includes(c.toLocaleLowerCase("de-DE")));
}

function localPlan(message: string, defaultCity?: string): { intent: string; shouldSearchEvents: boolean; filters: Filters; memoryProposal?: Json; goalProposal?: Json } {
  const q = message.toLocaleLowerCase("de-DE");
  const filters: Filters = {};
  const budget = q.match(/(?:unter|max(?:imal)?|bis|budget(?: von)?)\s*(\d{1,4})(?:\s*€|\s*euro)?/);
  if (budget) filters.max_budget = Number(budget[1]);
  if (/kostenlos|gratis|eintritt frei/.test(q)) filters.max_budget = 0;
  if (/ohne oper|keine oper/.test(q)) filters.exclude_opera = true;
  // Nutzerfeedback: "Datenanbindung ... nur auf ausgewählter Stadt
  // basierend" -- ohne explizit im Text genannte Stadt fällt der Filter
  // jetzt auf die im Client gerade gewählte Stadt zurück (siehe
  // "city_id"/"city_name" im Request-Body), statt implizit alle Städte
  // zu durchsuchen.
  filters.city = explicitCityIn(message) ?? defaultCity;
  const music = ["barock", "oper", "sinfonie", "symphonie", "kammermusik", "chor", "klavier", "mozart", "bach", "mahler", "beethoven"];
  // Nutzerfeedback: "keinen Anschluss ... wenn man sie ueber echte Konzerte
  // oder Daten fragen will" -- schlaegt der externe Planungsaufruf fehl oder
  // liefert keinen query-Filter, kannte der lokale Fallback bislang nur eine
  // feste Genre-Wortliste. Venue-/Kuenstlernamen (z.B. "Isarphilharmonie")
  // gehen als Grossschreibungs-Eigennamen in den Originaltext daher als
  // Fallback-Suchbegriff ein.
  // Nutzerfeedback: "Konzerte diesen Monat in der Isarphilharmonie" fand
  // nichts, obwohl echte Events existieren -- Ursache war, dass diese
  // Heuristik den ERSTEN grossgeschriebenen Wort-Treffer nimmt. Im Deutschen
  // sind aber ALLE Substantive grossgeschrieben, also traf sie hier
  // "Konzerte" statt "Isarphilharmonie" und die SQL-Suche lief komplett ins
  // Leere. Fix: eine breitere Liste generischer, in Konzert-Anfragen
  // typischer Substantive ausschliessen UND den LETZTEN Treffer statt den
  // ersten nehmen -- Venue-/Künstlernamen stehen in natürlicher deutscher
  // Formulierung fast immer am Ende, nach Präpositionen wie "in der/im/von".
  // Nutzerfeedback (zweiter Anlauf): "Empfiehl mir ein Konzert unter 30
  // Euro" fing danach faelschlich "Euro" als Suchbegriff (letzter groko-
  // geschriebener Treffer nach dem Ausschluss von "Konzert") und schraenkte
  // die Suche unnoetig ein. Zwei zusaetzliche Sicherungen: ein negativer
  // Lookbehind schliesst Woerter direkt nach einer Zahl aus (Waehrungs-/
  // Einheitenangaben wie "30 Euro", "2 Stunden"), und die Stopwortliste
  // deckt jetzt auch gaengige Imperativ-Verben und Einheiten ab.
  const stopwords = new Set([
    "Ich", "Wie", "Was", "Wann", "Wo", "Gibt", "Kannst", "Bitte", "Zeig", "Zeige", "Suche", "Finde", "Klangradar",
    "Empfiehl", "Erklaere", "Erkläre", "Sag", "Zeigt", "Hilf", "Waehl", "Wähl", "Plane", "Buche",
    "Konzert", "Konzerte", "Veranstaltung", "Veranstaltungen", "Termin", "Termine", "Ticket", "Tickets", "Karte", "Karten",
    "Monat", "Monate", "Woche", "Wochen", "Wochenende", "Tag", "Tage", "Abend", "Abende", "Musik", "Programm",
    "Euro", "Stunden", "Stunde", "Minuten", "Minute", "Prozent", "Grad", "Uhr",
  ]);
  const properNoun = message
    .match(/(?<!\d\s)[A-ZÄÖÜ][\wÀ-ÿ'-]{2,}(?:\s[A-ZÄÖÜ][\wÀ-ÿ'-]{2,})?/g)
    ?.filter((w) => !stopwords.has(w.split(" ")[0]))
    .pop();
  filters.query = music.find((word) => q.includes(word)) ?? properNoun;
  const target = new Date();
  if (/übermorgen/.test(q)) target.setDate(target.getDate() + 2);
  else if (/morgen/.test(q)) target.setDate(target.getDate() + 1);
  else if (/samstag/.test(q)) target.setDate(target.getDate() + ((6 - target.getDay() + 7) % 7 || 7));
  else if (/sonntag/.test(q)) target.setDate(target.getDate() + ((7 - target.getDay()) % 7 || 7));
  if (/heute|morgen|übermorgen|samstag|sonntag/.test(q)) Object.assign(filters, dateRange(target));
  else if (/nächsten monat/.test(q)) Object.assign(filters, monthRange(1));
  else if (/diesen monat/.test(q)) Object.assign(filters, monthRange(0));
  const search = /find|such|empfiehl|konzert|abend|wochenende|heute|morgen|samstag|sonntag|monat/.test(q);
  const intent = /warum|profil|geschmack/.test(q) ? "explain_profile" : /trend|häufig|meistens|langfristig/.test(q) ? "behavior_trend" : /plan|abend/.test(q) ? "plan_evening" : search ? "find_events" : "general";
  return { intent, shouldSearchEvents: search, filters: Object.fromEntries(Object.entries(filters).filter(([, v]) => v !== undefined)) };
}

function safeObject(raw: unknown): Json | undefined {
  if (typeof raw !== "string" || !raw.trim()) return undefined;
  try { const parsed = JSON.parse(raw); return parsed && typeof parsed === "object" && !Array.isArray(parsed) ? parsed : undefined; } catch { return undefined; }
}

// Der Client wird ohne generierte Database-Typen initialisiert; `any` ist
// hier bewusst auf diese kleine Adaptergrenze begrenzt.
// deno-lint-ignore no-explicit-any
async function loadDashboard(db: any, userID: string) {
  const [{ data: context }, { data: trends }, { data: saved }, { data: existing }] = await Promise.all([
    db.rpc("coach_context_snapshot"), db.rpc("coach_behavior_trends"),
    db.from("favorites").select("status,events(id,slug,title,start_datetime,remaining_tickets_status)").eq("user_id", userID),
    db.from("coach_insights").select("*").is("dismissed_at", null).or(`valid_until.is.null,valid_until.gt.${new Date().toISOString()}`).order("priority", { ascending: false }).limit(12),
  ]);
  const now = Date.now();
  const generated: Json[] = [];
  for (const row of (saved ?? []) as Array<{ events: Json | null }>) {
    const event = row.events as unknown as Json | null;
    if (!event || typeof event.start_datetime !== "string") continue;
    const hours = (new Date(event.start_datetime).getTime() - now) / 3_600_000;
    if (hours > 0 && hours <= 168) generated.push({
      user_id: userID, kind: "planning", fingerprint: `upcoming:${event.id}`,
      title: hours <= 36 ? "Dein Konzert steht kurz bevor" : "Diese Woche geplant",
      body: `${event.title} ist ${hours <= 36 ? "bald" : "diese Woche"}. Soll ich Anreise, Einlass und den restlichen Abend mit dir planen?`,
      evidence: [{ type: "event", id: event.id }], actions: [{ type: "open_event", slug: event.slug }, { type: "ask_coach", prompt: `Plane meinen Abend rund um ${event.title}` }],
      priority: hours <= 36 ? 3 : 2, valid_until: event.start_datetime,
    });
    if (event.remaining_tickets_status === "few_left") generated.push({
      user_id: userID, kind: "ticket", fingerprint: `few-left:${event.id}`,
      title: "Wenige Tickets", body: `Für ${event.title} sind nur noch wenige Tickets gemeldet.`,
      evidence: [{ type: "event", id: event.id }], actions: [{ type: "open_event", slug: event.slug }], priority: 3, valid_until: event.start_datetime,
    });
  }
  if (generated.length) await db.from("coach_insights").upsert(generated, { onConflict: "user_id,fingerprint", ignoreDuplicates: true });
  const all = [...(existing ?? []), ...generated].filter((item, index, rows) => rows.findIndex((x) => x.fingerprint === item.fingerprint) === index);
  return { context: context ?? {}, trends: trends ?? [], insights: all.sort((a, b) => Number(b.priority ?? 0) - Number(a.priority ?? 0)).slice(0, 12) };
}

// deno-lint-ignore no-explicit-any
async function loadContext(db: any) {
  const [{ data: context }, { data: trends }] = await Promise.all([db.rpc("coach_context_snapshot"), db.rpc("coach_behavior_trends")]);
  return { context: context ?? {}, trends: trends ?? [] };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Nur POST" }, 405);
  const db = createClient(Deno.env.get("SUPABASE_URL") ?? "", Deno.env.get("SUPABASE_ANON_KEY") ?? "", { global: { headers: { Authorization: `Bearer ${bearer(req)}` } } });
  const { data: authData } = await db.auth.getUser();
  if (!authData.user) return json({ error: "Bitte anmelden, damit die Klangradar KI persönliche Daten sicher verwenden kann." }, 401);
  let body: Json;
  try { body = await req.json(); } catch { return json({ error: "Ungültige Anfrage" }, 400); }
  const action = String(body.action ?? "dashboard");

  if (action === "dashboard") return json(await loadDashboard(db, authData.user.id));
  if (action === "checkin") {
    const values = { user_id: authData.user.id, mood: body.mood ?? null, energy: body.energy ?? null, available_minutes: body.available_minutes ?? null, budget: body.budget ?? null, companion: body.companion ?? null, note: String(body.note ?? "").slice(0, 500) || null };
    const { data, error } = await db.from("coach_checkins").insert(values).select().single();
    return error ? json({ error: error.message }, 400) : json({ checkin: data });
  }
  if (action === "confirm_memory") {
    const proposal = body.proposal as Json | undefined;
    if (!proposal || !proposal.category || !proposal.label || proposal.value === undefined) return json({ error: "Ungültiger Memory-Vorschlag" }, 400);
    const { data, error } = await db.from("coach_memory_items").insert({ user_id: authData.user.id, category: proposal.category, label: String(proposal.label).slice(0, 120), value: proposal.value, source: "user_confirmed", confirmed_at: new Date().toISOString() }).select().single();
    return error ? json({ error: error.message }, 400) : json({ memory: data });
  }
  if (action === "confirm_goal") {
    const proposal = body.proposal as Json | undefined;
    if (!proposal || !proposal.kind || !proposal.title) return json({ error: "Ungültiger Ziel-Vorschlag" }, 400);
    const { data, error } = await db.from("coach_goals").insert({ user_id: authData.user.id, kind: proposal.kind, title: String(proposal.title).slice(0, 160), target_value: proposal.target_value ?? null, period: proposal.period ?? null, metadata: proposal.metadata ?? {} }).select().single();
    return error ? json({ error: error.message }, 400) : json({ goal: data });
  }
  if (action === "dismiss_insight") {
    const { error } = await db.from("coach_insights").update({ dismissed_at: new Date().toISOString() }).eq("id", body.insight_id);
    return error ? json({ error: error.message }, 400) : json({ ok: true });
  }
  if (action !== "chat") return json({ error: "Unbekannte Aktion" }, 400);

  const message = String(body.message ?? "").trim().slice(0, 1400);
  if (!message) return json({ error: "Nachricht fehlt" }, 400);
  // Nutzerfeedback: "Datenanbindung ... nur auf ausgewählter Stadt
  // basierend" -- der Client schickt jetzt die im Stadt-Chip gewählte
  // Stadt mit, damit "kommende Konzerte in der Isarphilharmonie" auch
  // ohne einen Stadtnamen im Satz auf die aktuell gewählte Stadt
  // eingegrenzt wird, statt implizit über alle Städte zu suchen.
  const defaultCity = typeof body.city_name === "string" && body.city_name.trim() ? body.city_name.trim() : undefined;
  // Chat braucht nur Kontext/Trends fuer den Prompt, keine Insights/Favoriten
  // (die macht nur die "dashboard"-Aktion) -- spart pro Chat-Nachricht mehrere
  // DB-Roundtrips und einen Upsert, die sowieso nie in die Antwort einfliessen.
  const dashboard = await loadContext(db);
  let local = localPlan(message, defaultCity);
  const planned = await callAiFunctionPreferGemini(
    "Du bist der Planer der Klangradar KI. Verwende niemals die Bezeichnung Coach. Extrahiere nur die Absicht. Erfinde keine Events, Daten oder Präferenzen. Relative Daten beziehen sich auf " + new Date().toISOString() + ". Memory nur vorschlagen, wenn der Nutzer ausdrücklich 'merk dir' o.ä. sagt; Ziele nur bei klarer Zielsetzung.",
    `Nachricht: ${message}\nBestätigter Kontext: ${JSON.stringify(dashboard.context)}`,
    PLAN_FUNCTION,
  );
  let provider = planned?.provider ?? "local";
  let memoryProposal: Json | undefined;
  let goalProposal: Json | undefined;
  if (planned) {
    local = {
      intent: String(planned.args.intent ?? local.intent),
      shouldSearchEvents: Boolean(planned.args.shouldSearchEvents),
      filters: { ...local.filters, ...(safeObject(planned.args.filtersJson) as Filters | undefined ?? {}) },
    };
    // Der externe Planungsaufruf bekommt keine Anweisung, "city" nur bei
    // ausdrücklicher Nennung zu füllen -- ein von der KI selbst geratener
    // Stadtname (oder ein fehlender) würde sonst den korrekten
    // Default-auf-aktuelle-Stadt oben überschreiben. Gleiche Regel wie in
    // localPlan() hier erzwungen, unabhängig davon, was die KI geliefert hat.
    local.filters.city = explicitCityIn(message) ?? defaultCity;
    memoryProposal = safeObject(planned.args.memoryProposalJson);
    goalProposal = safeObject(planned.args.goalProposalJson);
  }
  // Nutzerfeedback: "Konzerte heute" fand nichts, obwohl welche existieren --
  // der externe Planer lieferte date_from/date_to als IDENTISCHES Datum ohne
  // Uhrzeit (z.B. beide "2026-09-05"), wodurch coach_search_events' Bereich
  // start_datetime>=date_from AND start_datetime<date_to leer wird. Schutz:
  // liegt date_to nicht sichtbar NACH date_from, wird auf einen vollen Tag
  // ab date_from erweitert.
  if (local.filters.date_from) {
    const from = new Date(local.filters.date_from);
    const to = local.filters.date_to ? new Date(local.filters.date_to) : undefined;
    if (!Number.isNaN(from.getTime()) && (!to || Number.isNaN(to.getTime()) || to.getTime() <= from.getTime())) {
      local.filters.date_to = new Date(from.getTime() + 24 * 3600 * 1000).toISOString();
    }
  }
  let events: Json[] = local.shouldSearchEvents
    ? ((await db.rpc("coach_search_events", { p_filters: local.filters, p_limit: 8 })).data as Json[] | null) ?? []
    : [];
  // Nutzerfeedback: "falls es mal kein passendes Konzert gibt, soll er
  // immer Alternativen vorschlagen" -- statt einer leeren Antwort werden
  // die Filter schrittweise gelockert (erst der Freitext, dann zusätzlich
  // Budget/Genre-Ausschluss), bis etwas gefunden wird oder nur noch Stadt
  // und Zeitraum übrig sind. usedRelaxedSearch fließt in den Antworttext.
  let usedRelaxedSearch = false;
  if (local.shouldSearchEvents && events.length === 0) {
    const relaxedFilterSets: Filters[] = [
      { city: local.filters.city, date_from: local.filters.date_from, date_to: local.filters.date_to, max_budget: local.filters.max_budget },
      { city: local.filters.city, date_from: local.filters.date_from, date_to: local.filters.date_to },
    ];
    for (const relaxed of relaxedFilterSets) {
      const { data } = await db.rpc("coach_search_events", { p_filters: relaxed, p_limit: 4 });
      if (Array.isArray(data) && data.length > 0) { events = data as Json[]; usedRelaxedSearch = true; break; }
    }
  }
  const evidence = [
    { type: "context_snapshot", signal_quality: (dashboard.context as Json).signal_quality },
    ...(events.map((e) => ({ type: "event", id: e.id, slug: e.slug, reasons: e.reasons }))),
  ];
  const answerResult = await callAiFunctionPreferGemini(
    `Du bist die persönliche Klangradar KI. Verwende niemals die Bezeichnung Coach. Antworte warm, klar und präzise in 2-3 kurzen Absätzen. Nutze ausschließlich gelieferte Daten. Nenne Verhaltenstrends nur als Zusammenhang, nie als Ursache. Bei signal_quality=low sage, dass du die Person noch kennenlernst. Eventnamen nur aus Echte Treffer. Gib eine konkrete nächste Aktion.${usedRelaxedSearch ? " Zur Anfrage selbst gab es keinen exakten Treffer -- sag das offen und biete die gelieferten Treffer ausdrücklich als Alternativen an." : ""}`,
    `Frage: ${message}\nIntent: ${local.intent}\nPersönlicher Kontext: ${JSON.stringify(dashboard.context)}\nBeobachtete Trends: ${JSON.stringify(dashboard.trends)}\nEchte Treffer${usedRelaxedSearch ? " (Alternativen, keine exakte Übereinstimmung)" : ""}: ${JSON.stringify(events ?? [])}`,
    ANSWER_FUNCTION,
  );
  if (answerResult) provider = answerResult.provider;
  const eventCount = events.length;
  const fallbackAnswer = local.shouldSearchEvents
    ? eventCount
      ? usedRelaxedSearch
        ? `Genau dazu finde ich gerade keine exakte Übereinstimmung. Hier sind ${eventCount} Alternativen, die zeitlich und vom Ort her trotzdem passen könnten.\n\nÖffne einen Treffer für Details – oder sag mir, was ich anders suchen soll.`
        : `Ich habe ${eventCount} passende Veranstaltungen gefunden. Die Reihenfolge berücksichtigt deine bestätigten Interessen, dein aktuelles Check-in und deine bisherigen Aktionen.\n\nÖffne einen Treffer für Programm, Tickets und Venue-Informationen – oder sag mir, was ich ändern soll, zum Beispiel „günstiger“, „früher“ oder „etwas Neues“.`
      : "Dazu finde ich gerade keine echte Veranstaltung in Klangradar, auch nicht mit gelockerten Filtern. Ich kann Datum, Budget, Ort oder Musikrichtung ändern, ohne den restlichen Gesprächskontext zu verlieren."
    : "Ich lerne deinen Kulturrhythmus aus bestätigten Interessen, gespeicherten Events, Ticket- und Kalenderaktionen sowie freiwilligen Check-ins. Je mehr belastbare Signale vorliegen, desto konkreter kann ich erklären, warum etwas zu dir passt."
  const answer = String(answerResult?.args.answer ?? fallbackAnswer);
  const suggestedPrompts = Array.isArray(answerResult?.args.suggestedPrompts) ? answerResult!.args.suggestedPrompts.map(String).slice(0, 4) : ["Was passt dieses Wochenende zu mir?", "Erkläre mein Geschmacksprofil", "Plane einen Abend unter 50 €"];
  let conversationID = typeof body.conversation_id === "string" ? body.conversation_id : undefined;
  if (!conversationID) {
    const { data } = await db.from("coach_conversations").insert({ user_id: authData.user.id }).select("id").single();
    conversationID = data?.id;
  }
  const actions = [
    ...events.map((e) => ({ type: "open_event", event_id: e.id, slug: e.slug, label: "Event öffnen" })),
    ...(memoryProposal ? [{ type: "confirm_memory", proposal: memoryProposal, label: "Merken" }] : []),
    ...(goalProposal ? [{ type: "confirm_goal", proposal: goalProposal, label: "Ziel übernehmen" }] : []),
  ];
  if (conversationID) await Promise.all([
    db.from("coach_messages").insert({ conversation_id: conversationID, role: "user", content: message, intent: local.intent }),
    db.from("coach_messages").insert({ conversation_id: conversationID, role: "assistant", content: answer, intent: local.intent, evidence, actions }),
    db.from("coach_conversations").update({ context: local.filters, updated_at: new Date().toISOString() }).eq("id", conversationID),
  ]);
  return json({ conversation_id: conversationID, answer, intent: local.intent, filters: local.filters, context: dashboard.context, trends: dashboard.trends, events, events_are_alternatives: usedRelaxedSearch, evidence, actions, memory_proposal: memoryProposal, goal_proposal: goalProposal, suggested_prompts: suggestedPrompts, provider });
});
