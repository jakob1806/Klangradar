"use client";

import { Analytics } from "@vercel/analytics/react";
import { useEffect, useState } from "react";

const key = "klangradar-analytics-consent";

export function ConsentAnalytics() {
  const [consent, setConsent] = useState<"yes" | "no" | null>(null);
  useEffect(() => setConsent(localStorage.getItem(key) as "yes" | "no" | null), []);
  if (consent === null) return <div className="fixed inset-x-4 bottom-4 z-50 mx-auto max-w-lg rounded-2xl border border-black/10 bg-white p-4 shadow-xl"><p className="text-sm font-semibold text-[#1d1d1f]">Datenschutz</p><p className="mt-1 text-xs leading-relaxed text-[#48484a]">Mit deiner Zustimmung messen wir anonym, welche Seiten genutzt werden. Details stehen in der Datenschutzerklärung.</p><div className="mt-3 flex gap-2"><button onClick={() => { localStorage.setItem(key, "no"); setConsent("no"); }} className="rounded-full border border-black/10 px-3 py-2 text-xs font-semibold">Ablehnen</button><button onClick={() => { localStorage.setItem(key, "yes"); setConsent("yes"); }} className="rounded-full bg-[#0071e3] px-3 py-2 text-xs font-semibold text-white">Akzeptieren</button></div></div>;
  return consent === "yes" ? <Analytics /> : null;
}
