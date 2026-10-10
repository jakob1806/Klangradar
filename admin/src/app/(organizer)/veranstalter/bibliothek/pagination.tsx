import Link from "next/link";
import { LIBRARY_PAGE_SIZE } from "@/lib/library-images";

export function LibraryPagination({ basePath, q, page, total }: { basePath: string; q: string; page: number; total: number }) {
  const pages = Math.max(1, Math.ceil(total / LIBRARY_PAGE_SIZE));
  if (pages <= 1) return null;
  const href = (target: number) => {
    const params = new URLSearchParams();
    if (q) params.set("q", q);
    if (target > 1) params.set("page", String(target));
    const query = params.toString();
    return query ? `${basePath}?${query}` : basePath;
  };
  const cls = "rounded-lg border border-[#e4e1ea] px-3 py-1.5 text-sm font-medium text-[#2D2A6E] hover:bg-[#2D2A6E]/5";
  return (
    <nav className="mt-8 flex items-center justify-between" aria-label="Seitennavigation">
      {page > 1 ? <Link className={cls} href={href(page - 1)}>← Zurück</Link> : <span />}
      <span className="text-sm text-[#6B6B6B]">Seite {page} von {pages}</span>
      {page < pages ? <Link className={cls} href={href(page + 1)}>Weiter →</Link> : <span />}
    </nav>
  );
}
