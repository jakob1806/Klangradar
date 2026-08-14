"use client";

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import {
  applyEditorialAiProposals,
  chatWithEditorialAi,
  loadEditorialAi,
  updateEditorialAiMemory,
  type EditorialAiEntityType,
  type EditorialAiProposal,
} from "@/lib/editorial-ai-actions";

type Message = { role: "user" | "assistant"; content: string; proposals?: EditorialAiProposal[] };

const FIELD_LABEL: Record<string, string> = {
  biography_de: "Biografie", birth_date: "Geburtsdatum", death_date: "Sterbedatum", nationality: "Nationalität",
  instrument: "Instrument", roles: "Rollen", education_career_de: "Ausbildung/Karriere", current_roles_de: "Aktuelle Rollen",
  description_de: "Beschreibung", founded_year: "Gründungsjahr", member_count: "Mitgliederzahl", leadership_de: "Leitung",
  residency_de: "Sitz/Residenz", repertoire_de: "Repertoire", title: "Titel", composer_id: "Komponist-ID",
  catalog_number: "Werkverzeichnis", key_signature: "Tonart", composition_year: "Entstehungsjahr", duration_minutes: "Dauer",
  movements: "Sätze", instrumentation: "Besetzung", alternative_titles: "Alternative Titel", program_notes_de: "Programmtext", start_datetime: "Beginn", end_datetime: "Ende",
  website_url: "Website", subtitle: "Untertitel", type: "Typ", genre: "Genre",
};

const DATE_FIELDS = new Set(["birth_date", "death_date"]);

function cleanText(value: string) {
  return value.replace(/^```(?:json|text|markdown)?\s*/i, "").replace(/\s*```$/i, "").replace(/\]\[/g, "").replace(/^[\s\[\]{}"']+/, "").replace(/[\s\[\]{}"']+$/, "").trim();
}

function editableValue(field: string, value: unknown) {
  if (DATE_FIELDS.has(field) && typeof value === "string") {
    const match = value.match(/^(\d{4})-(\d{2})-(\d{2})$/);
    if (match) return `${match[3]}.${match[2]}.${match[1]}`;
  }
  return Array.isArray(value) ? value.join("\n") : typeof value === "string" ? value : JSON.stringify(value);
}

function parsedValue(field: string, draft: string, original: unknown) {
  if (DATE_FIELDS.has(field)) {
    if (!/^\d{2}\.\d{2}\.\d{4}$/.test(draft.trim())) throw new Error(`${FIELD_LABEL[field]} muss als TT.MM.JJJJ eingegeben werden.`);
    return draft.trim();
  }
  if (Array.isArray(original)) return draft.split(/\n|,/).map((value) => value.trim()).filter(Boolean);
  if (typeof original === "number") {
    const number = Number(draft); if (!Number.isFinite(number)) throw new Error(`„${draft}“ ist keine gültige Zahl.`); return number;
  }
  if (typeof original === "boolean") return draft.trim().toLowerCase() === "true" || draft.trim().toLowerCase() === "ja";
  if (original !== null && typeof original === "object") return JSON.parse(draft);
  return ["biography_de", "description_de", "program_notes_de"].includes(field) ? cleanText(draft) : draft.trim();
}

export function EditorialAiAssistant({ entityType, entityId }: { entityType: EditorialAiEntityType; entityId: string }) {
  const router = useRouter();
  const [open, setOpen] = useState(false);
  const [loaded, setLoaded] = useState(false);
  const [messages, setMessages] = useState<Message[]>([]);
  const [input, setInput] = useState("");
  const [memory, setMemory] = useState("");
  const [showMemory, setShowMemory] = useState(false);
  const [selected, setSelected] = useState<Record<string, EditorialAiProposal>>({});
  const [drafts, setDrafts] = useState<Record<string, string>>({});
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();

  function toggle() {
    setOpen((value) => !value);
    if (!loaded) startTransition(async () => {
      try {
        const data = await loadEditorialAi(entityType, entityId);
        setMemory(data.memory ?? "");
        setMessages((data.messages ?? []).map((m: Message) => ({ role: m.role, content: m.content, proposals: m.proposals })));
        setLoaded(true);
      } catch (e) { setError(e instanceof Error ? e.message : "Laden fehlgeschlagen."); }
    });
  }

  function send() {
    const message = input.trim(); if (!message || pending) return;
    setInput(""); setError(null); setSuccess(null); setMessages((old) => [...old, { role: "user", content: message }]);
    startTransition(async () => {
      try {
        const data = await chatWithEditorialAi(entityType, entityId, message);
        setMessages((old) => [...old, { role: "assistant", content: data.answer, proposals: data.proposals }]);
      } catch (e) { setError(e instanceof Error ? e.message : "Recherche fehlgeschlagen."); }
    });
  }

  function apply() {
    let values: EditorialAiProposal[];
    try {
      values = Object.entries(selected).map(([key, proposal]) => ({
        ...proposal,
        value: parsedValue(proposal.field, drafts[key] ?? editableValue(proposal.field, proposal.value), proposal.value),
      }));
    } catch (e) { setError(e instanceof Error ? e.message : "Ungültiger Wert."); return; }
    if (!values.length) return;
    startTransition(async () => {
      try { const result = await applyEditorialAiProposals(entityType, entityId, values); setSelected({}); setDrafts({}); setError(null); setSuccess(`${result.appliedFields?.length ?? values.length} Felder wurden ins Profil übernommen.`); router.refresh(); }
      catch (e) { setError(e instanceof Error ? e.message : "Übernahme fehlgeschlagen."); }
    });
  }

  return (
    <section className="w-full max-w-3xl overflow-hidden rounded-3xl border border-[#d7d9ff] bg-white shadow-[0_10px_40px_rgba(63,81,181,0.10)]">
      <button type="button" onClick={toggle} className="flex w-full items-center justify-between bg-gradient-to-r from-[#f4f7ff] via-white to-[#faf4ff] px-5 py-4 text-left">
        <span className="flex items-center gap-3"><span className="bg-gradient-to-br from-[#4285f4] via-[#8b5cf6] to-[#ea4c89] bg-clip-text text-2xl text-transparent">✦</span><span><span className="block font-semibold text-[#24284a]">Gemini Recherche</span><span className="text-xs text-[#667085]">Websuche · Quellen · kontrollierte Übernahme</span></span></span>
        <span className="text-sm text-neutral-500">{open ? "Schließen" : "Öffnen"}</span>
      </button>
      {open && <div className="border-t border-[#e8eaff] bg-gradient-to-b from-[#fbfcff] to-white p-5">
        <div className="mb-3 flex justify-end"><button type="button" className="text-xs font-medium text-[#5b5bd6] hover:underline" onClick={() => setShowMemory(!showMemory)}>Festes Redaktionsprofil</button></div>
        {showMemory && <div className="mb-4 rounded-xl bg-white p-3">
          <textarea value={memory} onChange={(e) => setMemory(e.target.value)} rows={6} className="w-full resize-y rounded-lg border border-neutral-200 p-2 text-sm" />
          <button type="button" disabled={pending} onClick={() => startTransition(async () => { try { await updateEditorialAiMemory(memory); } catch (e) { setError(e instanceof Error ? e.message : "Speichern fehlgeschlagen."); } })} className="mt-2 rounded-full bg-gradient-to-r from-[#4776e6] to-[#8e54e9] px-4 py-2 text-xs font-medium text-white">Profil speichern</button>
        </div>}
        <div className="max-h-[32rem] space-y-3 overflow-y-auto pr-1">
          {messages.length === 0 && <p className="text-sm text-neutral-500">Frage nach Lebensdaten, Biografie, Besetzung, Werkangaben oder einer Prüfung vorhandener Informationen.</p>}
          {messages.map((message, index) => <div key={index} className={`rounded-2xl p-4 text-sm ${message.role === "user" ? "ml-12 bg-[#eef2ff] text-[#30345b]" : "mr-4 border border-[#e4e7ff] bg-white text-neutral-800 shadow-sm"}`}>
            <p className="whitespace-pre-wrap">{message.content}</p>
            {message.proposals?.map((proposal, proposalIndex) => {
              const key = `${index}-${proposalIndex}`; const disabled = proposal.confidence === "unclear";
              return <div key={key} className={`mt-3 block rounded-2xl border p-3 ${disabled ? "border-amber-200 bg-amber-50" : "border-[#d8dcff] bg-[#f8f9ff]"}`}>
                <label className="flex gap-2"><input type="checkbox" disabled={disabled} checked={!!selected[key]} onChange={(e) => setSelected((old) => { const next = { ...old }; if (e.target.checked) next[key] = proposal; else delete next[key]; return next; })} />
                  <span><strong>{FIELD_LABEL[proposal.field] ?? proposal.field}</strong><span className="ml-2 text-[11px] uppercase text-neutral-500">{proposal.confidence}</span></span>
                </label>
                <textarea
                  value={drafts[key] ?? editableValue(proposal.field, proposal.value)}
                  onChange={(event) => setDrafts((old) => ({ ...old, [key]: event.target.value }))}
                  rows={proposal.field === "biography_de" || proposal.field === "description_de" ? 7 : Array.isArray(proposal.value) ? 3 : 2}
                  disabled={disabled}
                  className="mt-2 w-full resize-y rounded-xl border border-[#dfe2f4] bg-white p-3 text-sm outline-none focus:border-[#7c6cf2] focus:ring-2 focus:ring-[#7c6cf2]/15 disabled:bg-neutral-100"
                  aria-label={`${FIELD_LABEL[proposal.field] ?? proposal.field} vor Übernahme bearbeiten`}
                />
                {proposal.rationale && <p className="mt-1 pl-6 text-xs text-neutral-600">{proposal.rationale}</p>}
                {!!proposal.sourceUrls?.length && <div className="mt-1 flex flex-wrap gap-2 pl-6">{proposal.sourceUrls.map((url) => <a key={url} href={url} target="_blank" rel="noreferrer" className="truncate text-xs text-blue-700 underline">Quelle</a>)}</div>}
              </div>;
            })}
          </div>)}
          {pending && <p className="text-sm text-neutral-500">Gemini recherchiert…</p>}
        </div>
        {Object.keys(selected).length > 0 && <button type="button" disabled={pending} onClick={apply} className="mt-3 rounded-full bg-gradient-to-r from-[#4776e6] to-[#8e54e9] px-5 py-2.5 text-sm font-medium text-white shadow-md disabled:opacity-50">{Object.keys(selected).length} ausgewählte Felder ins Profil übernehmen</button>}
        {success && <p className="mt-3 rounded-xl border border-emerald-200 bg-emerald-50 px-3 py-2 text-sm text-emerald-800">✓ {success}</p>}
        {error && <p className="mt-3 text-sm text-red-700">{error}</p>}
        <div className="mt-4 flex gap-2 rounded-2xl border border-[#dfe2f4] bg-white p-2 shadow-sm focus-within:border-[#7c6cf2]"><textarea value={input} onChange={(e) => setInput(e.target.value)} onKeyDown={(e) => { if (e.key === "Enter" && !e.shiftKey) { e.preventDefault(); send(); } }} rows={2} placeholder="Gemini etwas recherchieren lassen …" className="min-w-0 flex-1 resize-none border-0 bg-transparent p-2 text-sm outline-none" /><button type="button" onClick={send} disabled={pending || !input.trim()} className="self-end rounded-full bg-gradient-to-r from-[#4776e6] to-[#8e54e9] px-5 py-2 text-sm font-medium text-white disabled:opacity-40">Senden</button></div>
      </div>}
    </section>
  );
}
