import Link from "next/link";
import { ConfirmButton } from "@/components/confirm-button";
import {
  EntityAuditBulkSelection,
  EntityAuditSelectCheckbox,
} from "@/components/entity-audit-bulk-selection";
import { EntityAuditFixButton } from "@/components/entity-audit-fix-button";
import { RunEntityAuditButton } from "@/components/run-entity-audit-button";
import { createClient } from "@/lib/supabase/server";
import {
  resolveEntityAuditFlag,
  type AuditableEntityType,
  type EntityAuditCorrection,
} from "@/lib/entity-audit-actions";

export const dynamic = "force-dynamic";

const TABS: { type: AuditableEntityType; label: string }[] = [
  { type: "person", label: "Personen" },
  { type: "ensemble", label: "Ensembles" },
  { type: "venue", label: "Venues" },
  { type: "event", label: "Veranstaltungen" },
];

const ENTITY_ROUTE: Record<AuditableEntityType, string> = {
  person: "persons",
  ensemble: "ensembles",
  venue: "venues",
  event: "events",
};

const TAB_DESCRIPTION: Record<AuditableEntityType, string> = {
  person: "Fehlerhafte, unvollständige oder ungewöhnliche Namen von Solist:innen, Dirigent:innen, Komponist:innen.",
  ensemble: "Fehlerhafte Namen sowie unplausible Gründungsjahre/Mitgliederzahlen von Orchestern und Chören.",
  venue: "Unvollständige Adressen sowie unplausible Postleitzahlen/Kapazitäten.",
  event: "Auffällige Titel sowie widersprüchliche Preis-/Dauerangaben und fehlende Venue-Zuordnung.",
};

interface AuditIssue {
  id: string;
  severity: "critical" | "warning" | "info";
  category: string;
  message: string;
  suggestion?: string | null;
  source: "rule" | "ai";
  aiCorrection?: EntityAuditCorrection;
}

interface FlagRow {
  id: string;
  entity_id: string;
  display_name: string;
  issues: AuditIssue[];
  created_at: string;
}

const SEVERITY_STYLE: Record<AuditIssue["severity"], string> = {
  critical: "border-red-200 bg-red-50 text-red-800",
  warning: "border-amber-200 bg-amber-50 text-amber-900",
  info: "border-blue-200 bg-blue-50 text-blue-800",
};

const SEVERITY_LABEL: Record<AuditIssue["severity"], string> = {
  critical: "Kritisch",
  warning: "Warnung",
  info: "Hinweis",
};

const SEVERITY_DOT: Record<AuditIssue["severity"], string> = {
  critical: "bg-red-500",
  warning: "bg-amber-500",
  info: "bg-blue-500",
};

const TYPE_ICON: Record<AuditableEntityType, string> = {
  person: "P",
  ensemble: "E",
  venue: "V",
  event: "K",
};

function highestSeverity(issues: AuditIssue[]): AuditIssue["severity"] {
  if (issues.some((issue) => issue.severity === "critical")) return "critical";
  if (issues.some((issue) => issue.severity === "warning")) return "warning";
  return "info";
}

function formatDate(iso: string) {
  return new Date(iso).toLocaleString("de-DE", { timeZone: "Europe/Berlin", dateStyle: "medium", timeStyle: "short" });
}

export default async function QualitaetspruefungPage({
  searchParams,
}: {
  searchParams: Promise<{ type?: string }>;
}) {
  const params = await searchParams;
  const activeType: AuditableEntityType = TABS.some((t) => t.type === params.type)
    ? (params.type as AuditableEntityType)
    : "person";

  const supabase = await createClient();
  const [{ data, error }, countResults] = await Promise.all([
    supabase
      .from("entity_audit_flags")
      .select("id, entity_id, display_name, issues, created_at")
      .eq("entity_type", activeType)
      .eq("status", "open")
      .order("display_name")
      .returns<FlagRow[]>(),
    Promise.all(
      TABS.map(async (tab) => {
        const { count } = await supabase
          .from("entity_audit_flags")
          .select("id", { count: "exact", head: true })
          .eq("entity_type", tab.type)
          .eq("status", "open");
        return [tab.type, count ?? 0] as const;
      }),
    ),
  ]);
  const counts = new Map<AuditableEntityType, number>(countResults);
  const activeCount = counts.get(activeType) ?? 0;
  const criticalCount = (data ?? []).filter((flag) => highestSeverity(flag.issues) === "critical").length;
  const withCorrectionCount = (data ?? []).filter((flag) => flag.issues.some((issue) => issue.aiCorrection)).length;

  return (
    <div className="mx-auto max-w-6xl p-6 lg:p-8">
      <div className="rounded-2xl border border-black/[0.06] bg-gradient-to-br from-white to-neutral-50 p-5 shadow-sm">
        <div className="flex flex-wrap items-start justify-between gap-4">
          <div>
            <p className="text-xs font-semibold uppercase tracking-[0.16em] text-[#0071e3]">Redaktion</p>
            <h1 className="mt-1 text-2xl font-semibold tracking-tight text-neutral-950">Qualitätsprüfung</h1>
            <p className="mt-1 max-w-2xl text-sm leading-6 text-neutral-500">{TAB_DESCRIPTION[activeType]}</p>
          </div>
          <RunEntityAuditButton entityType={activeType} />
        </div>

        <div className="mt-5 grid grid-cols-3 gap-2 sm:max-w-lg">
          <div className="rounded-xl border border-neutral-200 bg-white px-3 py-2.5">
            <p className="text-2xl font-semibold tabular-nums text-neutral-950">{activeCount}</p>
            <p className="text-[11px] text-neutral-500">Offene Treffer</p>
          </div>
          <div className="rounded-xl border border-red-100 bg-red-50/60 px-3 py-2.5">
            <p className="text-2xl font-semibold tabular-nums text-red-700">{criticalCount}</p>
            <p className="text-[11px] text-red-700/70">Kritisch</p>
          </div>
          <div className="rounded-xl border border-violet-100 bg-violet-50/60 px-3 py-2.5">
            <p className="text-2xl font-semibold tabular-nums text-violet-700">{withCorrectionCount}</p>
            <p className="text-[11px] text-violet-700/70">KI-Vorschläge</p>
          </div>
        </div>
      </div>

      <div className="mt-5 grid grid-cols-2 gap-2 lg:grid-cols-4">
        {TABS.map((tab) => (
          <Link
            key={tab.type}
            href={`/qualitaetspruefung?type=${tab.type}`}
            className={`flex items-center gap-3 rounded-xl border px-3 py-3 text-sm font-medium transition-all ${
              tab.type === activeType
                ? "border-[#0071e3]/30 bg-blue-50 text-[#0064c8] shadow-sm"
                : "border-neutral-200 bg-white text-neutral-600 hover:border-neutral-300 hover:text-neutral-900"
            }`}
          >
            <span
              className={`flex h-8 w-8 items-center justify-center rounded-lg text-xs font-semibold ${
                tab.type === activeType ? "bg-[#0071e3] text-white" : "bg-neutral-100 text-neutral-500"
              }`}
            >
              {TYPE_ICON[tab.type]}
            </span>
            <span className="min-w-0 flex-1">{tab.label}</span>
            <span className="rounded-full bg-black/[0.05] px-2 py-0.5 text-xs tabular-nums">{counts.get(tab.type) ?? 0}</span>
          </Link>
        ))}
      </div>

      {error && <p className="mt-6 text-sm text-amber-700">Konnte Prüfungen nicht laden: {error.message}</p>}

      {!error && (
        <EntityAuditBulkSelection ids={(data ?? []).map((flag) => flag.id)}>
        <div className="mt-3 flex flex-col gap-3">
          {data && data.length > 0 ? (
            data.map((flag) => {
              const severity = highestSeverity(flag.issues);
              const initialCorrection = flag.issues.find((issue) => issue.aiCorrection)?.aiCorrection ?? null;
              return (
              <article key={flag.id} className="overflow-hidden rounded-2xl border border-black/[0.07] bg-white shadow-sm">
                <div className={`h-1 ${SEVERITY_DOT[severity]}`} />
                <div className="p-4 sm:p-5">
                <div className="flex flex-wrap items-start justify-between gap-4">
                  <div className="min-w-0 flex-1">
                    <div className="flex flex-wrap items-center gap-2">
                      <Link
                        href={`/${ENTITY_ROUTE[activeType]}/${flag.entity_id}`}
                        className="text-base font-semibold text-neutral-950 hover:text-[#0071e3]"
                      >
                        {flag.display_name || "(kein Name)"}
                      </Link>
                      <span className={`rounded-full px-2 py-0.5 text-[10px] font-semibold ${SEVERITY_STYLE[severity]}`}>
                        {SEVERITY_LABEL[severity]}
                      </span>
                      <span className="text-xs text-neutral-400">
                        {flag.issues.length} {flag.issues.length === 1 ? "Auffälligkeit" : "Auffälligkeiten"}
                      </span>
                      <span className="text-xs text-neutral-400">{formatDate(flag.created_at)}</span>
                    </div>
                    <ul className="mt-3 space-y-2">
                      {flag.issues.map((issue) => (
                        <li
                          key={issue.id}
                          className={`rounded-lg border px-3 py-2 text-xs leading-5 ${SEVERITY_STYLE[issue.severity]}`}
                        >
                          <span className="font-medium">{issue.message}</span>
                          {issue.suggestion && <span className="opacity-90"> — {issue.suggestion}</span>}
                          <span className="ml-2 rounded bg-white/50 px-1.5 py-0.5 text-[10px] opacity-70">
                            {issue.source === "ai" ? "KI-Prüfung" : "Regelprüfung"}
                          </span>
                        </li>
                      ))}
                    </ul>
                    <EntityAuditFixButton
                      entityType={activeType}
                      entityId={flag.entity_id}
                      flagId={flag.id}
                      issueMessage={flag.issues.map((i) => i.message).join(" ")}
                      issueSuggestion={flag.issues.map((i) => i.suggestion).filter(Boolean).join(" ") || null}
                      initialCorrection={initialCorrection}
                    />
                  </div>
                  <div className="flex shrink-0 flex-col items-end gap-2">
                    <EntityAuditSelectCheckbox id={flag.id} label={flag.display_name || "Eintrag"} />
                    <Link
                      href={`/${ENTITY_ROUTE[activeType]}/${flag.entity_id}`}
                      className="text-xs font-medium text-neutral-700 hover:text-[#0071e3]"
                    >
                      Bearbeiten →
                    </Link>
                    <ConfirmButton
                      action={resolveEntityAuditFlag.bind(null, flag.id)}
                      confirmMessage="Als erledigt markieren?"
                      label="Erledigt"
                      pendingLabel="…"
                      className="border-2 border-emerald-700 bg-white px-2.5 py-1.5 text-xs font-medium text-emerald-700 hover:bg-emerald-50 disabled:opacity-50"
                    />
                  </div>
                </div>
                </div>
              </article>
              );
            })
          ) : (
            <div className="rounded-2xl border border-dashed border-emerald-200 bg-emerald-50/50 px-6 py-12 text-center">
              <div className="mx-auto flex h-10 w-10 items-center justify-center rounded-full bg-emerald-100 text-lg text-emerald-700">✓</div>
              <p className="mt-3 text-sm font-medium text-emerald-900">Keine offenen Auffälligkeiten</p>
              <p className="mt-1 text-xs text-emerald-700/70">Mit dem Prüfen-Button kannst du einen neuen Durchlauf starten.</p>
            </div>
          )}
        </div>
        </EntityAuditBulkSelection>
      )}
    </div>
  );
}
