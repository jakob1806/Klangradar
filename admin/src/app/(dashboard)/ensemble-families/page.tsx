import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { deleteEnsembleResolutionRule } from "../ensembles/actions";
import { ResolutionRuleForm, type FamilyOption } from "./resolution-rule-form";

export const dynamic = "force-dynamic";

const ROLE_LABELS: Record<string, string> = {
  institution: "Dachorganisation", orchestra: "Orchester", choir: "Chor",
  childrens_choir: "Kinderchor", extra_choir: "Extra-/Zusatzchor", ballet: "Ballett",
  opera_studio: "Opernstudio", statisterie: "Statisterie", child_statisterie: "Kinderstatisterie",
  other: "Weitere Untergruppe",
};

interface EnsembleRow {
  id: string; name: string; type: string; parent_ensemble_id: string | null;
  family_role: string | null; is_family_root: boolean; is_resolution_placeholder: boolean;
}
interface RuleRow { id: string; family_root_id: string | null; input_name: string; action: "expand" | "ignore"; note: string | null }
interface TargetRow { rule_id: string; ensemble_id: string; display_order: number }

export default async function EnsembleFamiliesPage({ searchParams }: { searchParams: Promise<{ automatisch?: string; q?: string }> }) {
  const { automatisch, q = "" } = await searchParams;
  const supabase = await createClient();
  const [{ data: ensembleData, error: ensembleError }, { data: ruleData, error: ruleError }, { data: targetData }] = await Promise.all([
    supabase.from("ensembles").select("id,name,type,parent_ensemble_id,family_role,is_family_root,is_resolution_placeholder").order("name").returns<EnsembleRow[]>(),
    supabase.from("ensemble_resolution_rules").select("id,family_root_id,input_name,action,note").order("input_name").returns<RuleRow[]>(),
    supabase.from("ensemble_resolution_rule_targets").select("rule_id,ensemble_id,display_order").order("display_order").returns<TargetRow[]>(),
  ]);
  const ensembles = ensembleData ?? [];
  const roots = ensembles.filter((item) => item.is_family_root);
  const stable = ensembles.filter((item) => !item.is_family_root && !item.is_resolution_placeholder);
  const placeholders = ensembles.filter((item) => item.is_resolution_placeholder);
  const names = new Map(ensembles.map((item) => [item.id, item.name]));
  const targetsByRule = new Map<string, TargetRow[]>();
  for (const target of targetData ?? []) targetsByRule.set(target.rule_id, [...(targetsByRule.get(target.rule_id) ?? []), target]);
  const families: FamilyOption[] = roots.map((root) => ({
    id: root.id,
    name: root.name,
    children: stable.filter((child) => child.parent_ensemble_id === root.id).map((child) => ({ id: child.id, name: child.name, role: child.family_role })),
  }));
  const unresolved = (ruleData ?? []).filter((rule) => rule.action === "expand" && !(targetsByRule.get(rule.id)?.length));
  const needle = q.trim().toLocaleLowerCase("de");
  const visibleFamilies = families.filter((family) => !needle || family.name.toLocaleLowerCase("de").includes(needle) || family.children.some((child) => child.name.toLocaleLowerCase("de").includes(needle)));
  const visibleRules = (ruleData ?? []).filter((rule) => !needle || rule.input_name.toLocaleLowerCase("de").includes(needle) || (targetsByRule.get(rule.id) ?? []).some((target) => names.get(target.ensemble_id)?.toLocaleLowerCase("de").includes(needle)));

  return (
    <div className="space-y-6 p-8">
      <header className="flex flex-wrap items-start justify-between gap-4">
        <div>
          <h1 className="text-xl font-semibold tracking-tight">Ensemblefamilien</h1>
          <p className="mt-1 max-w-3xl text-sm text-neutral-500">Dachorganisationen, echte Unterensembles und automatisch aufgelöste Sammelbezeichnungen an einem Ort.</p>
        </div>
        <Link href="/ensembles" className="rounded-xl border border-black/10 bg-white px-4 py-2 text-sm font-medium shadow-sm hover:bg-neutral-50">Alle Ensembles</Link>
      </header>

      <div className="rounded-2xl border border-black/[0.06] bg-white p-2 shadow-sm">
        <nav className="flex flex-wrap items-center gap-1">
          <a href="#familien" className="rounded-xl bg-[#0071e3] px-4 py-2 text-sm font-medium text-white">Familien</a>
          <a href="#aufloesungen" className="rounded-xl px-4 py-2 text-sm font-medium text-neutral-600 hover:bg-black/[0.05]">Auflösungen</a>
          <a href="#manuell" className="rounded-xl px-4 py-2 text-sm font-medium text-neutral-600 hover:bg-black/[0.05]">Manuelle Ausnahme</a>
          <form className="ml-auto flex min-w-64 gap-2" action="/ensemble-families">
            <input name="q" defaultValue={q} placeholder="Familie, Ensemble oder Regel suchen …" className="min-w-0 flex-1 rounded-xl border border-black/10 bg-neutral-50 px-3 py-2 text-sm outline-none focus:border-[#0071e3]" />
            <button className="rounded-xl border border-black/10 px-3 py-2 text-sm font-medium hover:bg-neutral-50">Suchen</button>
          </form>
        </nav>
      </div>

      {(ensembleError || ruleError) && <p className="border border-red-200 bg-red-50 p-4 text-sm text-red-700">Daten konnten nicht vollständig geladen werden: {ensembleError?.message ?? ruleError?.message}</p>}
      {automatisch === "1" && <p className="border border-emerald-200 bg-emerald-50 p-4 text-sm text-emerald-800">Die eingegebene Bezeichnung wurde automatisch auf bestehende Unterensembles aufgelöst; es wurde kein doppelter Stammdatensatz angelegt.</p>}

      <section className="grid gap-3 sm:grid-cols-4">
        {[["Familien", roots.length], ["Unterensembles", stable.filter((item) => item.parent_ensemble_id).length], ["Auflösungsregeln", ruleData?.length ?? 0], ["Ohne Ziel", unresolved.length]].map(([label, value]) => (
          <div key={label} className="rounded-2xl border border-black/[0.06] bg-white p-5 shadow-sm"><p className="type-label">{label}</p><p className="mt-2 text-3xl font-semibold tracking-tight">{value}</p></div>
        ))}
      </section>

      <section id="familien" className="scroll-mt-6">
        <div className="flex items-end justify-between"><div><h2 className="text-lg font-semibold">Familienstruktur</h2><p className="mt-1 text-sm text-neutral-500">Dachorganisationen mit ihren eindeutig zugeordneten Unterensembles.</p></div>{needle && <span className="rounded-full bg-black/[0.05] px-3 py-1 text-xs text-neutral-600">{visibleFamilies.length} Treffer</span>}</div>
        <div className="mt-3 grid gap-4 xl:grid-cols-2">
          {visibleFamilies.map((family) => (
            <article key={family.id} className="rounded-2xl border border-black/[0.06] bg-white p-5 shadow-sm transition-shadow hover:shadow-md">
              <div className="flex items-center justify-between gap-3"><Link href={`/ensembles/${family.id}`} className="font-semibold hover:text-[#0071e3]">{family.name}</Link><span className="type-label border border-violet-200 bg-violet-50 px-2 py-1 !text-violet-700">Dachorganisation</span></div>
              <div className="mt-4 grid gap-2 sm:grid-cols-2">
                {family.children.map((child) => (
                  <Link key={child.id} href={`/ensembles/${child.id}`} className="flex items-center justify-between gap-2 rounded-xl bg-black/[0.035] px-3 py-2.5 text-sm hover:bg-[#0071e3]/[0.07] hover:text-[#0068d1]">
                    <span>{child.name}</span><span className="text-xs text-neutral-400">{ROLE_LABELS[child.role ?? ""] ?? child.role ?? "Ohne Rolle"}</span>
                  </Link>
                ))}
                {!family.children.length && <p className="text-sm text-amber-700">Noch keine Unterensembles zugeordnet.</p>}
              </div>
            </article>
          ))}
          {!visibleFamilies.length && <div className="col-span-full rounded-2xl border border-dashed border-black/10 bg-white p-8 text-center text-sm text-neutral-500">Keine passende Ensemblefamilie gefunden.</div>}
        </div>
      </section>

      <section id="aufloesungen" className="scroll-mt-6 space-y-3">
        <div><h2 className="text-base font-semibold">Automatisch erkannte Auflösungen</h2><p className="mt-1 text-sm text-neutral-500">Diese Zuordnungen entstehen aus Hausname, Rollenbegriffen und den vorhandenen „Gehört zu“-Beziehungen. Eine manuelle Regelpflege ist nicht erforderlich.</p></div>
        {visibleRules.map((rule) => {
          const targetIds = (targetsByRule.get(rule.id) ?? []).map((target) => target.ensemble_id);
          return (
            <article key={rule.id} className={`rounded-2xl border bg-white p-5 shadow-sm ${rule.action === "expand" && !targetIds.length ? "border-amber-300" : "border-black/[0.06]"}`}>
              <div className="flex flex-wrap items-start justify-between gap-3"><div><p className="font-medium">{rule.input_name}</p>{rule.note && <p className="mt-1 text-sm text-neutral-500">{rule.note}</p>}</div><span className="type-label border border-emerald-200 bg-emerald-50 px-2 py-1 !text-emerald-700">Automatisch erkannt</span></div>
              <div className="mt-3 border-t border-neutral-100 pt-3 text-sm text-neutral-600">{rule.action === "ignore" ? "Wird nicht als festes Ensemble gespeichert" : targetIds.length ? `→ ${targetIds.map((id) => names.get(id) ?? id).join(" + ")}` : "⚠ Konnte noch nicht eindeutig aufgelöst werden"}</div>
              <details className="mt-4 border-t border-neutral-100 pt-3"><summary className="cursor-pointer text-sm font-medium text-[#0071e3]">Manuell korrigieren</summary><div className="mt-4"><ResolutionRuleForm families={families} rule={{ id: rule.id, familyRootId: rule.family_root_id, inputName: rule.input_name, action: rule.action, note: rule.note, targetIds }} /><form action={deleteEnsembleResolutionRule} className="mt-3 text-right"><input type="hidden" name="id" value={rule.id} /><button className="text-xs text-red-600 hover:underline">Manuelle/automatische Regel löschen</button></form></div></details>
            </article>
          );
        })}
      </section>

      <section id="manuell" className="scroll-mt-6 space-y-3"><div><h2 className="text-lg font-semibold">Manuelle Ausnahme ergänzen</h2><p className="mt-1 text-sm text-neutral-500">Nur verwenden, wenn die automatische Erkennung eine offizielle Sonderbezeichnung nicht eindeutig zuordnen kann.</p></div><div className="rounded-2xl border border-[#0071e3]/20 bg-[#f5f9ff] p-5"><ResolutionRuleForm families={families} /></div></section>

      {placeholders.length > 0 && <section><h2 className="text-base font-semibold">Technische Sammelbezeichnungen</h2><p className="mt-1 text-sm text-neutral-500">Diese Datensätze bleiben nur für die Revisionshistorie erhalten und erscheinen nicht in den Apps oder Mitwirkenden-Auswahlen.</p><div className="mt-3 flex flex-wrap gap-2">{placeholders.map((item) => <Link key={item.id} href={`/ensembles/${item.id}`} className="border border-amber-200 bg-amber-50 px-3 py-2 text-sm text-amber-800 hover:border-amber-400">{item.name}</Link>)}</div></section>}
    </div>
  );
}
