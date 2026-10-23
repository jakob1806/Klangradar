import { NextResponse } from "next/server";
import { sendWeeklyDigests } from "@/lib/newsletter";

// Erstellt von Claude Code. Wöchentlich (vercel.json): "Deine Konzertwoche".
export const dynamic = "force-dynamic";
export const maxDuration = 300;

export async function GET(request: Request) {
  const secret = process.env.CRON_SECRET;
  if (!secret) return NextResponse.json({ error: "CRON_SECRET fehlt" }, { status: 500 });
  if (request.headers.get("authorization") !== `Bearer ${secret}`) return NextResponse.json({ error: "Nicht autorisiert" }, { status: 401 });
  return NextResponse.json(await sendWeeklyDigests());
}
