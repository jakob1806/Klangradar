"use client";

import { useRouter } from "next/navigation";
import { useState, useTransition } from "react";
import { finishWorkImageReuse, runWorkImageReusePage } from "@/lib/work-image-reuse-actions";

export function RunWorkImageReuseButton() {
  const router = useRouter();
  const [pending, startTransition] = useTransition();
  const [error, setError] = useState<string | null>(null);
  const [summary, setSummary] = useState<string | null>(null);
  const [progress, setProgress] = useState<string | null>(null);

  function handleClick() {
    setError(null);
    setSummary(null);
    startTransition(async () => {
      let offset = 0;
      let totalChecked = 0;
      let totalFilled = 0;
      try {
        for (;;) {
          const page = await runWorkImageReusePage(offset);
          totalChecked += page.checkedInPage;
          totalFilled += page.filledInPage;
          setProgress(`${Math.min(totalChecked, page.totalCount)} / ${page.totalCount} geprüft…`);
          offset += page.checkedInPage;
          if (page.done || page.checkedInPage === 0) break;
        }
        await finishWorkImageReuse();
        setSummary(`${totalChecked} bildlose Veranstaltungen geprüft, ${totalFilled} Bild${totalFilled === 1 ? "" : "er"} verknüpft`);
        setProgress(null);
        router.refresh();
      } catch (runError) {
        setError(runError instanceof Error ? runError.message : "Die Prüfung ist fehlgeschlagen.");
        setProgress(null);
      }
    });
  }

  return (
    <div className="flex flex-col items-end gap-1">
      <button
        type="button"
        disabled={pending}
        onClick={handleClick}
        className="rounded-lg border border-violet-200 bg-violet-50 px-3 py-1.5 text-[13px] font-medium text-violet-900 transition-colors hover:bg-violet-100 disabled:cursor-wait disabled:opacity-60"
      >
        {pending ? "Prüft bildlose Veranstaltungen…" : "Werk-Bilder verknüpfen"}
      </button>
      {progress && <p className="max-w-xs text-right text-xs text-neutral-500">{progress}</p>}
      {error && <p role="alert" className="max-w-xs text-right text-xs text-red-600">{error}</p>}
      {summary && <p className="max-w-xs text-right text-xs text-neutral-500">{summary}</p>}
    </div>
  );
}
