import Image from "next/image";
import Link from "next/link";

export default function PublicLayout({ children }: { children: React.ReactNode }) {
  return (
    <div className="apple-font flex min-h-screen flex-col">
      <a href="#main-content" className="skip-link">Zum Inhalt springen</a>
      <header className="sticky top-0 z-10 flex items-center justify-between border-b border-black/5 bg-white/70 px-6 py-3.5 backdrop-blur-xl">
        <Link href="/" aria-label="Klangradar Startseite" className="flex items-center gap-2.5 rounded-lg">
          <span className="dashboard-brand-mark" aria-hidden="true">
            <Image src="/app-logo.svg" alt="" width={34} height={34} />
          </span>
          <span className="text-[0.95rem] font-semibold tracking-tight text-[#1d1d1f]">Klangradar</span>
        </Link>
        <div className="flex items-center gap-2">
          <Link
            href="/veranstalter"
            className="rounded-full border border-black/10 px-4 py-2 text-sm font-semibold text-[#48484a] transition hover:bg-black/[0.04] active:scale-[0.985]"
          >
            Veranstalterportal
          </Link>
          <Link
            href="/login?redirectTo=/events"
            className="rounded-full bg-[#0071e3] px-4 py-2 text-sm font-semibold text-white transition hover:bg-[#0077ed] active:scale-[0.985]"
          >
            Anmelden als Admin
          </Link>
        </div>
      </header>

      <main id="main-content" tabIndex={-1} className="flex-1">{children}</main>

      <footer className="flex items-center justify-center gap-6 px-6 py-8 text-xs text-[#86868b]">
        <Link href="/impressum" className="hover:text-[#1d1d1f]">
          Impressum
        </Link>
        <Link href="/datenschutz" className="hover:text-[#1d1d1f]">
          Datenschutz
        </Link>
      </footer>
    </div>
  );
}
