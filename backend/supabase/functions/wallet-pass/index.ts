// Erstellt von Claude Code (02.11.2026): Konzertkarte für Apple Wallet.
// GET /wallet-pass?slug=<event-slug>&entrance=&block=&row=&seat=
// Liefert eine signierte .pkpass-Datei (application/vnd.apple.pkpass).
// 08.11.2026: dunkle Karte mit Klangradar-Logo und Logo-Bändern im Streifen, und –
// wenn die App im hinterlegten Ticket einen Code erkannt hat – dessen
// Inhalt als echter Barcode (&code=…&format=qr|aztec|pdf417|code128),
// damit die Karte am Einlass gescannt werden kann.
//
// Secrets (in Supabase → Edge Functions → Secrets):
//   WALLET_P12_BASE64    – Pass-Type-ID-Zertifikat samt Schlüssel (.p12, base64)
//   WALLET_P12_PASSWORD  – Passwort der .p12
//   WALLET_PASS_TYPE_ID  – z. B. pass.de.klangradar.konzert
//   WALLET_TEAM_ID       – Apple-Team-ID
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import forge from "npm:node-forge@1.3.1";
import { strToU8, zipSync } from "npm:fflate@0.8.2";
import { PASS_IMAGES } from "../_shared/walletPassImages.ts";
import { walletAuthToken } from "../_shared/walletToken.ts";
// Bildbibliothek erst bei Bedarf laden (08.11.2026): scheitert sie, wird
// die Karte trotzdem erstellt – nur ohne Streifenbild.
// 09.11.2026: statisch importiert – der dynamische Import wurde beim Deploy
// nicht mitgebündelt und schlug zur Laufzeit immer fehl (Karten ohne Bild).
// 09.11.2026 (2): Auch der statische Import ließ die Funktion beim Start
// abstürzen (WORKER_ERROR). Bildbearbeitung auf dem Server ist deshalb aus;
// den Bildstreifen erzeugt die App und schickt ihn mit (POST).
// deno-lint-ignore no-explicit-any
const Image: any = null;
let stripNote = "";
async function loadImageLib(): Promise<boolean> {
  if (Image) return true;
  stripNote = "imagelib-missing";
  return false;
}

const WWDR_URL = "https://www.apple.com/certificateauthority/AppleWWDRCAG4.cer";
let wwdrCache: forge.pki.Certificate | null = null;

async function wwdr(): Promise<forge.pki.Certificate> {
  if (wwdrCache) return wwdrCache;
  const der = new Uint8Array(await (await fetch(WWDR_URL)).arrayBuffer());
  wwdrCache = forge.pki.certificateFromAsn1(forge.asn1.fromDer(forge.util.binary.raw.encode(der)));
  return wwdrCache;
}

function signerFromP12(): { cert: forge.pki.Certificate; key: forge.pki.PrivateKey } {
  const p12Der = forge.util.decode64(Deno.env.get("WALLET_P12_BASE64") ?? "");
  const p12 = forge.pkcs12.pkcs12FromAsn1(forge.asn1.fromDer(p12Der), Deno.env.get("WALLET_P12_PASSWORD") ?? "");
  const cert = p12.getBags({ bagType: forge.pki.oids.certBag })[forge.pki.oids.certBag]?.[0]?.cert;
  const key = p12.getBags({ bagType: forge.pki.oids.pkcs8ShroudedKeyBag })[forge.pki.oids.pkcs8ShroudedKeyBag]?.[0]?.key
    ?? p12.getBags({ bagType: forge.pki.oids.keyBag })[forge.pki.oids.keyBag]?.[0]?.key;
  if (!cert || !key) throw new Error("Zertifikat oder Schlüssel fehlt in der .p12");
  return { cert, key };
}

/** Streifenbild: Kartenfarbe + zwei Bänder (Violettblau oben, Mint unten),
 * die von einem Punkt rechts der Mitte schräg nach außen laufen. */
// deno-lint-ignore no-explicit-any
function logoBandStrip(w: number, h: number): any {
  const ox = w * 0.62, oy = h / 2;
  const half = h * 0.15;
  const stemW = half * 2.1;
  const len = Math.hypot(1, 0.7);
  const dirs: Array<[number, number, number[]]> = [[1 / len, -0.7 / len, [113, 128, 251]], [1 / len, 0.7 / len, [82, 205, 188]]];
  const mix = (c: number, a: number, b: number) => Math.round(c * a + b * (1 - a));
  const image = new Image(w, h);
  image.fill((x: number, y: number) => {
    const px = x - ox, py = y - oy;
    if (px >= 0) {
      for (const [dx, dy, c] of dirs) {
        const edge = half - Math.abs(px * dy - py * dx);
        if (edge > 0) {
          const a = Math.min(1, edge);
          return Image.rgbaToColor(mix(c[0], a, 26), mix(c[1], a, 27), mix(c[2], a, 46), 255);
        }
      }
    } else if (px > -stemW) {
      // Stamm des K, dezent
      return Image.rgbaToColor(mix(255, 0.12, 26), mix(255, 0.12, 27), mix(255, 0.12, 46), 255);
    }
    return Image.rgbaToColor(26, 27, 46, 255);
  });
  return image;
}

function hashString(value: string): number {
  let h = 0;
  for (let i = 0; i < value.length; i++) h = (h * 31 + value.charCodeAt(i)) >>> 0;
  return h;
}

/** Konzertbild laden und prüfen: dekodierbar (JPEG/PNG), groß genug,
 * querformatig genug. Sonst null → Plakat oder Logo-Bänder. */
async function loadPhoto(url: string | null): Promise<any> {
  if (!url || !/^https:\/\//.test(url)) return null;
  // 09.11.2026: direkt, sonst über einen Bild-Proxy als JPEG – manche Hosts
  // (mphil.de, gaertnerplatztheater.de) sind aus Supabase nicht erreichbar,
  // und WebP kann die Bildbibliothek nicht lesen.
  const proxied = `https://wsrv.nl/?url=${encodeURIComponent(url)}&output=jpg&w=1000&q=85`;
  for (const target of [url, proxied]) {
    try {
      const res = await fetch(target, { signal: AbortSignal.timeout(target === url ? 3500 : 6000) });
      if (!res.ok) continue;
      const bytes = new Uint8Array(await res.arrayBuffer());
      if (bytes.length > 6_000_000) continue; // zu groß für die Rechenzeit
      if (bytes[0] === 0x52 && bytes[8] === 0x57 && bytes[9] === 0x45) continue; // WebP
      const image = await Image.decode(bytes);
      if (image.width < 300 || image.height < 160) return null;
      return image.width > 1000 ? image.resize(1000, Image.RESIZE_AUTO) : image;
    } catch {
      // nächster Weg
    }
  }
  return null;
}

/** A (09.11.2026): Foto füllt den Streifen; der Ausschnitt folgt dem
 * Motiv (focus 0…1 = senkrechte Bildmitte des Motivs, von der App per
 * Gesichts-/Motiverkennung bestimmt oder vom Nutzer verschoben). */
// deno-lint-ignore no-explicit-any
function photoStrip(source: any, w: number, h: number, focusX = 0.5, focusY = 0.35): any {
  const cover = Math.max(w / source.width, h / source.height);
  const scaled = source.clone().resize(Math.ceil(source.width * cover), Math.ceil(source.height * cover));
  const clamp = (v: number, max: number) => Math.max(0, Math.min(max, Math.round(v)));
  const x = clamp(scaled.width * focusX - w / 2, scaled.width - w);
  const y = clamp(scaled.height * focusY - h / 2, scaled.height - h);
  return scaled.crop(x, y, w, h);
}

let posterFont: Uint8Array | null = null;
async function loadPosterFont(): Promise<Uint8Array | null> {
  if (posterFont) return posterFont;
  try {
    const res = await fetch("https://raw.githubusercontent.com/google/fonts/main/ofl/dmserifdisplay/DMSerifDisplay-Regular.ttf", { signal: AbortSignal.timeout(6000) });
    if (!res.ok) return null;
    posterFont = new Uint8Array(await res.arrayBuffer());
    return posterFont;
  } catch {
    return null;
  }
}

/** A: Titel groß in Serifenschrift auf Schwarz. Wörter werden nie getrennt;
 * kurze Titel stehen in einer Zeile, lange werden kleiner und umbrechen.
 * Gemessen wird einmal bei Referenzgröße, dann proportional skaliert. */
async function posterStrip(title: string, w: number, h: number): Promise<any> {
  const font = await loadPosterFont();
  if (!font) return null;
  const pad = Math.round(w * 0.045);
  const words = title.replace(/\s+/g, " ").trim().split(" ");
  const ref = 100;
  const widthAt = new Map<string, number>();
  const measure = async (text: string) => {
    if (!widthAt.has(text)) widthAt.set(text, (await Image.renderText(font, ref, text, 0xffffffff)).width);
    return widthAt.get(text)!;
  };
  let best: { rows: string[]; size: number } | null = null;
  for (const lineCount of [1, 2, 3]) {
    if (lineCount > words.length) break;
    const per = Math.ceil(words.length / lineCount);
    const rows: string[] = [];
    for (let i = 0; i < words.length; i += per) rows.push(words.slice(i, i + per).join(" "));
    const widest = Math.max(...await Promise.all(rows.map(measure)));
    const byWidth = ((w - 2 * pad) / widest) * ref;
    const byHeight = (h - pad) / (rows.length * 0.98);
    const size = Math.floor(Math.min(byWidth, byHeight, h * 0.62));
    if (!best || size > best.size) best = { rows, size };
  }
  if (!best || best.size < h * 0.14) return null;
  const image = new Image(w, h);
  image.fill(Image.rgbaToColor(17, 17, 17, 255));
  const lineH = Math.round(best.size * 0.98);
  let y = h - pad * 0.6 - lineH * best.rows.length;
  for (const row of best.rows) {
    const r = await Image.renderText(font, best.size, row, 0xffffffff);
    image.composite(r, pad, Math.round(y + (lineH - r.height)));
    y += lineH;
  }
  return image;
}

// 09.11.2026: WebCrypto statt forge – forge.util.binary.raw.encode lief bei
// großen Bildern (> ~100 KB) in einen Stapelüberlauf (500).
async function sha1Hex(bytes: Uint8Array): Promise<string> {
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-1", bytes));
  return Array.from(digest, (b) => b.toString(16).padStart(2, "0")).join("");
}

function bytesToBase64(bytes: Uint8Array): string {
  let binary = "";
  for (let i = 0; i < bytes.length; i += 0x8000) binary += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  return btoa(binary);
}

function base64ToBytes(b64: string): Uint8Array {
  return Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
}

Deno.serve(async (req) => {
  const url = new URL(req.url);
  // 09.11.2026: Die App kann den fertigen Bildstreifen mitschicken (POST,
  // JSON {strip1x, strip2x, strip3x} als Base64-PNG). Dann braucht der Server
  // weder Bildbibliothek noch Zugriff auf die Bildquelle.
  // deno-lint-ignore no-explicit-any
  const posted: any = req.method === "POST" ? await req.json().catch(() => ({})) : {};
  const appStrips: Record<string, Uint8Array> = {};
  for (const [key, name] of [["strip1x", "strip.png"], ["strip2x", "strip@2x.png"], ["strip3x", "strip@3x.png"]] as const) {
    const raw = typeof posted?.[key] === "string" ? posted[key] : "";
    if (!raw || raw.length > 1_500_000) continue;
    try {
      const bytes = Uint8Array.from(atob(raw), (c) => c.charCodeAt(0));
      if (bytes[0] === 0x89 && bytes[1] === 0x50 && bytes[2] === 0x4e && bytes[3] === 0x47) appStrips[name] = bytes;
    } catch { /* ungültig → ignorieren */ }
  }
  let hasAppStrip = !!appStrips["strip@2x.png"];
  const slug = url.searchParams.get("slug");
  if (!slug) return new Response("slug fehlt", { status: 400 });
  const passTypeIdentifier = Deno.env.get("WALLET_PASS_TYPE_ID");
  const teamIdentifier = Deno.env.get("WALLET_TEAM_ID");
  if (!passTypeIdentifier || !teamIdentifier || !Deno.env.get("WALLET_P12_BASE64")) {
    return new Response("Wallet ist noch nicht eingerichtet", { status: 503 });
  }

  const db = createClient(Deno.env.get("SUPABASE_URL") ?? "", Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "");
  const { data: event } = await db.from("events")
    .select("id, slug, title, start_datetime, status, venue_id, image_urls, venues(name, address_street, address_city)")
    .eq("slug", slug).neq("status", "draft").maybeSingle();
  if (!event) return new Response("Konzert nicht gefunden", { status: 404 });
  // deno-lint-ignore no-explicit-any
  const venue = (event as any).venues as { name?: string; address_street?: string; address_city?: string; photo_url?: string } | null;
  const code = (url.searchParams.get("code") ?? "").slice(0, 2000);
  // Mehrere Tickets aus einem PDF: je Ticket eine Karte (08.11.2026).
  const ticketNo = Number(url.searchParams.get("ticket") ?? "") || 0;
  const ticketOf = Number(url.searchParams.get("of") ?? "") || 0;
  const formatMap: Record<string, string> = {
    qr: "PKBarcodeFormatQR", aztec: "PKBarcodeFormatAztec", pdf417: "PKBarcodeFormatPDF417", code128: "PKBarcodeFormatCode128",
  };
  const barcodeFormat = formatMap[(url.searchParams.get("format") ?? "qr").toLowerCase()] ?? "PKBarcodeFormatQR";


  // 09.11.2026: Reihenfolge wie auf dem Ticket, Bezeichnungen frei
  // („Rang“, „Sitz“, „Tür“), dazu weitere Angaben als extra=Bezeichnung|Wert.
  const seatDefaults: Record<string, string> = { block: "BLOCK", row: "REIHE", seat: "PLATZ", entrance: "EINGANG" };
  const seatParts = (["block", "row", "seat", "entrance"] as const)
    .map((k) => [k, (url.searchParams.get(k) ?? "").trim().slice(0, 30)] as const)
    .filter(([, v]) => v);
  const seatLabels: Record<string, string> = Object.fromEntries(Object.entries(seatDefaults).map(([k, d]) =>
    [k, ((url.searchParams.get(`${k}_label`) ?? "").trim().slice(0, 16).toUpperCase() || d)]));
  const seatExtras = url.searchParams.getAll("extra").slice(0, 4).map((raw, i) => {
    const [label, ...rest] = raw.split("|");
    return { key: `extra${i}`, label: (label ?? "").trim().slice(0, 16).toUpperCase(), value: rest.join("|").trim().slice(0, 30) };
  }).filter((e) => e.value);

  const serial = `${event.id}-${seatParts.map(([, v]) => v).join("-") || "karte"}${ticketNo ? `-t${ticketNo}` : ""}`.slice(0, 200);
  // deno-lint-ignore no-explicit-any
  const venueID = (event as any).venue_id as string | null;
  const { data: latlng } = venueID ? await db.rpc("venue_latlng", { p_venue: venueID }) : { data: null };
  const location = (latlng as Array<{ lat: number; lng: number }> | null)?.[0] ?? null;
  // Parameter merken, damit wallet-service die Karte später neu erzeugen kann.
  const keep = new URLSearchParams(url.searchParams);
  // Bildstreifen der App mitspeichern, damit Aktualisierungen über
  // wallet-service (ohne App) dasselbe Bild zeigen.
  if (!hasAppStrip) {
    const { data: stored } = await db.from("wallet_passes").select("strips").eq("serial", serial).maybeSingle();
    // deno-lint-ignore no-explicit-any
    const strips = (stored as any)?.strips as Record<string, string> | null;
    for (const [name, b64] of Object.entries(strips ?? {})) {
      try { appStrips[name] = Uint8Array.from(atob(b64), (c) => c.charCodeAt(0)); } catch { /* ignorieren */ }
    }
    hasAppStrip = !!appStrips["strip@2x.png"];
  }
  const stripsToStore = req.method === "POST" && hasAppStrip
    ? Object.fromEntries(Object.entries(appStrips).map(([n, b]) => [n, bytesToBase64(b)]))
    : undefined;
  await db.from("wallet_passes").upsert({ serial, event_id: event.id, params: keep.toString(), ...(stripsToStore ? { strips: stripsToStore } : {}) }, { onConflict: "serial" })
    .then(() => {}, () => {});
  const cancelled = (event as { status?: string }).status === "cancelled";

  const pass = {
    formatVersion: 1,
    passTypeIdentifier,
    teamIdentifier,
    serialNumber: serial,
    // 09.11.2026: Apple-Wallet-Webdienst – Karte aktualisiert sich, wenn sich
    // das Konzert ändert (wallet-service).
    webServiceURL: `${Deno.env.get("SUPABASE_URL")}/functions/v1/wallet-service/`,
    authenticationToken: await walletAuthToken(serial),
    // Am Konzertabend in der Nähe der Spielstätte auf dem Sperrbildschirm.
    ...(location ? { locations: [{ latitude: location.lat, longitude: location.lng, relevantText: `${event.title} – Viel Freude!` }] } : {}),
    organizationName: "Klangradar",
    description: `Konzert: ${event.title}`,
    logoText: "Klangradar",
    backgroundColor: "rgb(26, 27, 46)",
    foregroundColor: "rgb(255, 255, 255)",
    labelColor: "rgb(82, 205, 188)",
    relevantDate: event.start_datetime,
    ...(code ? {
      barcodes: [{ format: barcodeFormat, message: code, messageEncoding: "iso-8859-1" }],
      barcode: { format: barcodeFormat, message: code, messageEncoding: "iso-8859-1" },
    } : {}),
    semantics: {
      eventName: event.title,
      eventStartDate: event.start_datetime,
      ...(venue?.name ? { venueName: venue.name } : {}),
      eventType: "PKEventTypeLivePerformance",
    },
    eventTicket: {
      primaryFields: [{ key: "event", label: "KONZERT", value: event.title }],
      secondaryFields: [
        { key: "date", label: "BEGINN", value: event.start_datetime, dateStyle: "PKDateStyleMedium", timeStyle: "PKDateStyleShort" },
        ...(venue?.name ? [{ key: "venue", label: "ORT", value: venue.name }] : []),
      ],
      auxiliaryFields: [
        ...(cancelled ? [{ key: "status", label: "STATUS", value: "ABGESAGT" }] : []),
        ...seatParts.map(([k, v]) => ({ key: k, label: seatLabels[k], value: v })),
        // Apple zeigt höchstens vier Zusatzfelder vorn – der Rest steht hinten.
        ...seatExtras.slice(0, Math.max(0, 4 - seatParts.length)),
        ...(ticketNo && ticketOf > 1 ? [{ key: "ticket", label: "TICKET", value: `${ticketNo} von ${ticketOf}` }] : []),
      ],
      backFields: [
        ...seatExtras.slice(Math.max(0, 4 - seatParts.length)).map((e) => ({ ...e, key: `back_${e.key}` })),
        ...(venue?.address_street ? [{ key: "address", label: "Adresse", value: [venue.address_street, venue.address_city].filter(Boolean).join(", ") }] : []),
        { key: "link", label: "Konzertseite", value: `https://klangradar.com/e/${event.slug}` },
        { key: "hint", label: "Hinweis", value: code
          ? "Der Code stammt aus deinem hinterlegten Ticket. Im Zweifel gilt das Originalticket des Veranstalters."
          : "Diese Karte ersetzt nicht dein Ticket. Sie erinnert dich an Termin, Ort und Platz." },
      ],
    },
  };

  const files: Record<string, Uint8Array> = { "pass.json": strToU8(JSON.stringify(pass)) };
  for (const [name, b64] of Object.entries(PASS_IMAGES)) files[name] = base64ToBytes(b64);
  // 08.11.2026: Streifen-Design je nach Bildlage –
  //  B „Foto“: echtes Konzertbild, wenn es scharf/groß genug und lesbar ist,
  //  A „Plakat“: sonst der Titel groß in Serifenschrift (ohne Trennung),
  //  C „Logo-Bänder“: gelegentlich statt A und als Rückfall.
  const hasImageLib = hasAppStrip ? false : await loadImageLib();
  if (hasAppStrip) Object.assign(files, appStrips);
  // deno-lint-ignore no-explicit-any
  // 09.11.2026: mehrere Bildquellen probieren – Originale (JPEG/PNG) aus der
  // Bildtabelle zuerst, die gespeicherten WebP-Kopien kann die Bibliothek
  // nicht lesen.
  const { data: imageRows } = await db.from("images")
    .select("source_url, sort_order")
    .eq("origin_type", "event").eq("origin_id", event.id)
    .in("license_status", ["confirmed_free", "confirmed_licensed", "official_press_image"])
    .order("sort_order", { ascending: true }).limit(5);
  const appImage = (url.searchParams.get("image") ?? "").slice(0, 1000);
  const candidates = [
    appImage,
    ...((imageRows ?? []) as Array<{ source_url: string | null }>).map((r) => r.source_url),
    // deno-lint-ignore no-explicit-any
    ...(((event as any).image_urls ?? []) as string[]),
  ].filter((u): u is string => !!u && /^https:\/\//.test(u));
  let photo = null;
  if (hasImageLib) {
    for (const url of [...new Set(candidates)].slice(0, 5)) {
      photo = await loadPhoto(url);
      if (photo) break;
    }
    if (!photo) stripNote = `no-photo(${candidates.length})`;
  }
  const variant: "photo" | "poster" | "bands" = (photo || hasAppStrip) ? "photo"
    : (hashString(event.id) % 3 === 0 ? "bands" : "poster");
  let usedPoster = false;
  // 08.11.2026 (Absturz „worker_error“ = Rechenzeit-Limit): nur EIN Streifen
  // in 750×196 rechnen, die kleine Fassung daraus verkleinern; kein @3x.
  // deno-lint-ignore no-explicit-any
  let strip2x: any = null;
  try {
    if (hasImageLib && variant === "photo" && photo) {
      const f = (k: string, d: number) => {
        const v = Number(url.searchParams.get(k));
        return Number.isFinite(v) && url.searchParams.has(k) ? Math.max(0, Math.min(1, v)) : d;
      };
      strip2x = photoStrip(photo, 750, 196, f("focus_x", 0.5), f("focus_y", 0.35));
    }
    if (hasImageLib && variant === "poster") {
      strip2x = await posterStrip(event.title, 750, 196);
      if (strip2x) usedPoster = true;
    }
  } catch (err) {
    console.warn("wallet-pass strip", err instanceof Error ? err.message : String(err));
    stripNote = `strip-error:${err instanceof Error ? err.message.slice(0, 80) : "?"}`;
  }
  try {
    if (hasImageLib) {
      if (!strip2x) strip2x = logoBandStrip(750, 196);
      files["strip@2x.png"] = await strip2x.encode();
      files["strip.png"] = await strip2x.clone().resize(375, 98).encode();
    }
  } catch (err) {
    console.warn("wallet-pass strip encode", err instanceof Error ? err.message : String(err));
    stripNote = `encode-error:${err instanceof Error ? err.message.slice(0, 80) : "?"}`;
  }
  // Fotokarte: Titel unter den Streifen, damit das Bild frei bleibt.
  if (variant === "photo" && files["strip@2x.png"]) {
    pass.eventTicket.primaryFields = [];
    // 09.11.2026: Hat die App Titel und Programm groß ins Bild gesetzt,
    // nicht noch einmal klein darunter wiederholen.
    if (url.searchParams.get("title_in_strip") !== "1") {
      // deno-lint-ignore no-explicit-any
      (pass.eventTicket.secondaryFields as any[]).unshift({ key: "event", label: "KONZERT", value: event.title });
    }
  }
  // Beim Plakat steht der Titel schon im Bild – nicht doppelt darüberlegen.
  if (usedPoster) {
    pass.eventTicket.primaryFields = [];
    // Plakat: schwarze Karte, Beschriftungen im Violettblau des Logos.
    (pass as Record<string, unknown>).backgroundColor = "rgb(17, 17, 17)";
    (pass as Record<string, unknown>).labelColor = "rgb(155, 166, 255)";
  }
  // Erst jetzt serialisieren: Foto-/Plakat-Anpassungen oben ändern pass noch.
  files["pass.json"] = strToU8(JSON.stringify(pass));
  const manifest: Record<string, string> = {};
  for (const [name, bytes] of Object.entries(files)) manifest[name] = await sha1Hex(bytes);
  const manifestBytes = strToU8(JSON.stringify(manifest));

  // Schritt merken, damit ein Fehler ohne Log-Zugriff eingegrenzt werden kann
  // (02.11.2026). Gibt nie Passwort, Schlüssel oder Zertifikatsinhalt aus.
  let stage = "p12";
  try {
    const { cert, key } = signerFromP12();
    stage = "wwdr";
    const intermediate = await wwdr();
    stage = "sign";
    const p7 = forge.pkcs7.createSignedData();
    p7.content = forge.util.createBuffer(forge.util.binary.raw.encode(manifestBytes));
    p7.addCertificate(cert);
    p7.addCertificate(intermediate);
    p7.addSigner({
      key,
      certificate: cert,
      digestAlgorithm: forge.pki.oids.sha256,
      authenticatedAttributes: [
        { type: forge.pki.oids.contentType, value: forge.pki.oids.data },
        { type: forge.pki.oids.messageDigest },
        { type: forge.pki.oids.signingTime, value: new Date() as unknown as string },
      ],
    });
    p7.sign({ detached: true });
    stage = "zip";
    const signature = forge.util.binary.raw.decode(forge.asn1.toDer(p7.toAsn1()).getBytes());

    const zip = zipSync({ ...files, "manifest.json": manifestBytes, signature });
    return new Response(zip, {
      headers: {
        "Content-Type": "application/vnd.apple.pkpass",
        "Content-Disposition": `attachment; filename="${event.slug}.pkpass"`,
        "Cache-Control": "no-store",
        // Diagnose ohne Log-Zugriff: welches Streifen-Design, ggf. warum keins.
        "X-Klangradar-Strip": hasAppStrip ? "app" : (files["strip.png"] ? (usedPoster ? "poster" : (photo ? "photo" : "bands")) : "none") + (stripNote ? `;${stripNote}` : "").replace(/[^\x20-\x7e]/g, ""),
      },
    });
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    console.error("wallet-pass", stage, message);
    const hint: Record<string, string> = {
      p12: "Zertifikat (.p12) nicht lesbar – Passwort oder Base64 prüfen",
      wwdr: "Apple-Zwischenzertifikat nicht abrufbar",
      sign: "Signieren fehlgeschlagen",
      zip: "Paket konnte nicht erstellt werden",
    };
    // Nur Kategorie und eine gekürzte Fehlermeldung ohne Geheimnisse.
    const safe = message.replace(/[A-Za-z0-9+/=]{40,}/g, "…").slice(0, 160);
    return new Response(`Karte konnte nicht signiert werden (${stage}): ${hint[stage] ?? ""} – ${safe}`, { status: 500 });
  }
});
