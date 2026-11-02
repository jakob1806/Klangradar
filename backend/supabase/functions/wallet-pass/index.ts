// Erstellt von Claude Code (02.11.2026): Konzertkarte für Apple Wallet.
// GET /wallet-pass?slug=<event-slug>&entrance=&block=&row=&seat=
// Liefert eine signierte .pkpass-Datei (application/vnd.apple.pkpass).
// Kein Eintrittsticket: kein Barcode – nur Datum, Ort und eigener Platz,
// damit die Karte zur richtigen Zeit auf dem Sperrbildschirm erscheint.
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

function sha1Hex(bytes: Uint8Array): string {
  const md = forge.md.sha1.create();
  md.update(forge.util.binary.raw.encode(bytes));
  return md.digest().toHex();
}

function base64ToBytes(b64: string): Uint8Array {
  return Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
}

Deno.serve(async (req) => {
  const url = new URL(req.url);
  const slug = url.searchParams.get("slug");
  if (!slug) return new Response("slug fehlt", { status: 400 });
  const passTypeIdentifier = Deno.env.get("WALLET_PASS_TYPE_ID");
  const teamIdentifier = Deno.env.get("WALLET_TEAM_ID");
  if (!passTypeIdentifier || !teamIdentifier || !Deno.env.get("WALLET_P12_BASE64")) {
    return new Response("Wallet ist noch nicht eingerichtet", { status: 503 });
  }

  const db = createClient(Deno.env.get("SUPABASE_URL") ?? "", Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "");
  const { data: event } = await db.from("events")
    .select("id, slug, title, start_datetime, venues(name, address_street, address_city)")
    .eq("slug", slug).neq("status", "draft").maybeSingle();
  if (!event) return new Response("Konzert nicht gefunden", { status: 404 });
  // deno-lint-ignore no-explicit-any
  const venue = (event as any).venues as { name?: string; address_street?: string; address_city?: string } | null;

  const seatParts = (["entrance", "block", "row", "seat"] as const)
    .map((k) => [k, (url.searchParams.get(k) ?? "").trim().slice(0, 30)] as const)
    .filter(([, v]) => v);
  const seatLabels: Record<string, string> = { entrance: "EINGANG", block: "BLOCK", row: "REIHE", seat: "PLATZ" };

  const pass = {
    formatVersion: 1,
    passTypeIdentifier,
    teamIdentifier,
    serialNumber: `${event.id}-${seatParts.map(([, v]) => v).join("-") || "karte"}`,
    organizationName: "Klangradar",
    description: `Konzert: ${event.title}`,
    logoText: "Klangradar",
    backgroundColor: "rgb(20, 97, 148)",
    foregroundColor: "rgb(255, 255, 255)",
    labelColor: "rgb(200, 225, 240)",
    relevantDate: event.start_datetime,
    eventTicket: {
      primaryFields: [{ key: "event", label: "KONZERT", value: event.title }],
      secondaryFields: [
        { key: "date", label: "BEGINN", value: event.start_datetime, dateStyle: "PKDateStyleMedium", timeStyle: "PKDateStyleShort" },
        ...(venue?.name ? [{ key: "venue", label: "ORT", value: venue.name }] : []),
      ],
      auxiliaryFields: seatParts.map(([k, v]) => ({ key: k, label: seatLabels[k], value: v })),
      backFields: [
        ...(venue?.address_street ? [{ key: "address", label: "Adresse", value: [venue.address_street, venue.address_city].filter(Boolean).join(", ") }] : []),
        { key: "link", label: "Konzertseite", value: `https://klangradar.com/e/${event.slug}` },
        { key: "hint", label: "Hinweis", value: "Diese Karte ersetzt nicht dein Ticket. Sie erinnert dich an Termin, Ort und Platz." },
      ],
    },
  };

  const files: Record<string, Uint8Array> = { "pass.json": strToU8(JSON.stringify(pass)) };
  for (const [name, b64] of Object.entries(PASS_IMAGES)) files[name] = base64ToBytes(b64);
  const manifest: Record<string, string> = {};
  for (const [name, bytes] of Object.entries(files)) manifest[name] = sha1Hex(bytes);
  const manifestBytes = strToU8(JSON.stringify(manifest));

  try {
    const { cert, key } = signerFromP12();
    const p7 = forge.pkcs7.createSignedData();
    p7.content = forge.util.createBuffer(forge.util.binary.raw.encode(manifestBytes));
    p7.addCertificate(cert);
    p7.addCertificate(await wwdr());
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
    const signature = forge.util.binary.raw.decode(forge.asn1.toDer(p7.toAsn1()).getBytes());

    const zip = zipSync({ ...files, "manifest.json": manifestBytes, signature });
    return new Response(zip, {
      headers: {
        "Content-Type": "application/vnd.apple.pkpass",
        "Content-Disposition": `attachment; filename="${event.slug}.pkpass"`,
        "Cache-Control": "no-store",
      },
    });
  } catch (err) {
    console.error("wallet-pass", err);
    return new Response("Karte konnte nicht signiert werden", { status: 500 });
  }
});
