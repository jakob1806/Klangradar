"use client";

import { useState } from "react";
import { saveEnsembleResolutionRule } from "../ensembles/actions";

export interface FamilyOption {
  id: string;
  name: string;
  children: { id: string; name: string; role: string | null }[];
}

export interface RuleFormValue {
  id: string;
  familyRootId: string | null;
  inputName: string;
  action: "expand" | "ignore";
  note: string | null;
  targetIds: string[];
}

export function ResolutionRuleForm({ families, rule }: { families: FamilyOption[]; rule?: RuleFormValue }) {
  const [familyRootId, setFamilyRootId] = useState(rule?.familyRootId ?? families[0]?.id ?? "");
  const [action, setAction] = useState<"expand" | "ignore">(rule?.action ?? "expand");
  const children = families.find((family) => family.id === familyRootId)?.children ?? [];

  return (
    <form action={saveEnsembleResolutionRule} className="grid gap-3 lg:grid-cols-[1.35fr_1fr_0.7fr_1.4fr_auto] lg:items-end">
      {rule && <input type="hidden" name="id" value={rule.id} />}
      <label className="flex flex-col gap-1.5"><span className="type-label !text-neutral-600">Quellbezeichnung</span><input name="input_name" required defaultValue={rule?.inputName} placeholder="z. B. Chor und Kinderchor …" className="border border-neutral-300 px-3 py-2 text-sm outline-none focus:border-[#0071e3]" /></label>
      <label className="flex flex-col gap-1.5"><span className="type-label !text-neutral-600">Ensemblefamilie</span><select name="family_root_id" value={familyRootId} onChange={(event) => setFamilyRootId(event.target.value)} className="border border-neutral-300 bg-white px-3 py-2 text-sm outline-none focus:border-[#0071e3]">{families.map((family) => <option key={family.id} value={family.id}>{family.name}</option>)}</select></label>
      <label className="flex flex-col gap-1.5"><span className="type-label !text-neutral-600">Aktion</span><select name="action" value={action} onChange={(event) => setAction(event.target.value as "expand" | "ignore")} className="border border-neutral-300 bg-white px-3 py-2 text-sm outline-none focus:border-[#0071e3]"><option value="expand">Aufteilen</option><option value="ignore">Ignorieren</option></select></label>
      <label className="flex flex-col gap-1.5"><span className="type-label !text-neutral-600">Ziel-Ensembles</span><select name="target_ids" multiple required={action === "expand"} disabled={action === "ignore"} defaultValue={rule?.targetIds ?? []} className="min-h-20 border border-neutral-300 bg-white px-3 py-2 text-sm outline-none focus:border-[#0071e3] disabled:bg-neutral-100">{children.map((child) => <option key={child.id} value={child.id}>{child.name}</option>)}</select><span className="text-[11px] text-neutral-400">Mehrfachauswahl mit ⌘/Strg.</span></label>
      <button type="submit" className="bg-[#0071e3] px-4 py-2 text-sm font-medium text-white hover:bg-[#0077ed]">{rule ? "Korrektur speichern" : "Manuell anlegen"}</button>
      <label className="flex flex-col gap-1.5 lg:col-span-4"><span className="type-label !text-neutral-600">Redaktionelle Notiz</span><input name="note" defaultValue={rule?.note ?? ""} placeholder="Warum ist diese manuelle Zuordnung erforderlich?" className="border border-neutral-300 px-3 py-2 text-sm outline-none focus:border-[#0071e3]" /></label>
    </form>
  );
}
