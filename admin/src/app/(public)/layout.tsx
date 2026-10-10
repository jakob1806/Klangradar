import Image from "next/image";
import Link from "next/link";
import type { Metadata } from "next";
import { createClient } from "@/lib/supabase/server";

export const metadata: Metadata = { robots: { index: true, follow: true } };

// Eine einzige Server-seitige Auth-Prüfung für alle öffentlichen Seiten
// (/, /impressum, /datenschutz) statt in jeder Page erneut — entscheidet
// nur, ob der Button oben rechts "Anmelden als Admin" oder "Zum
// Adminportal" zeigt. Die eigentliche Zugriffskontrolle bleibt weiterhin
// proxy.ts (redirect nach /no-access), hier geht es nur um die Beschriftung.
async function resolveAdminCta() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    return { href: "/login?redirectTo=/events", label: "Anmelden als Admin" };
  }

  const { data: roles } = await supabase.from("user_roles").select("role").eq("user_id", user.id);
  const isAuthorized = roles?.some((r) => r.role === "admin" || r.role === "editor");

  return isAuthorized
    ? { href: "/events", label: "Zum Adminportal" }
    : { href: "/login?redirectTo=/events", label: "Anmelden als Admin" };
}

export default async function PublicLayout({ children }: { children: React.ReactNode }) {
  const cta = await resolveAdminCta();

  return (
    <div className="flex min-h-screen flex-col bg-white text-[#111111]">
      <header className="sticky top-0 z-20 border-b border-[#EAEAEA] bg-white">
        <div className="mx-auto flex h-16 max-w-6xl items-center justify-between gap-4 px-6">
          <Link href="/" className="flex items-center gap-2.5">
            <span className="dashboard-brand-mark" aria-hidden="true">
              <Image src="/app-logo.svg" alt="" width={34} height={34} />
            </span>
            <span className="text-[15px] font-semibold tracking-[-0.01em]">Klangradar</span>
          </Link>
          <nav aria-label="Hauptnavigation" className="flex items-center gap-2">
            <Link
              href="/veranstalter"
              className="hidden rounded-lg border border-[#DADADA] px-4 py-2 text-[14px] font-medium text-[#111111] hover:border-[#111111] sm:inline-flex"
            >
              Veranstalterportal
            </Link>
            <Link
              href={cta.href}
              className="rounded-lg bg-[#2D2A6E] px-4 py-2 text-[14px] font-medium text-white hover:bg-[#1F1D52]"
            >
              {cta.label}
            </Link>
          </nav>
        </div>
      </header>

      <main className="flex-1">{children}</main>

      <footer className="border-t border-[#EAEAEA]">
        <div className="mx-auto flex max-w-6xl flex-col gap-4 px-6 py-10 text-[13px] text-[#6B6B6B] sm:flex-row sm:items-center sm:justify-between">
          <span>© {new Date().getFullYear()} Klangradar</span>
          <nav aria-label="Rechtliches" className="flex gap-6">
            <Link href="/impressum" className="fw-link hover:text-[#111111]">
              Impressum
            </Link>
            <Link href="/datenschutz" className="fw-link hover:text-[#111111]">
              Datenschutz
            </Link>
            <Link href="/nutzungsbedingungen" className="fw-link hover:text-[#111111]">
              Nutzungsbedingungen
            </Link>
          </nav>
        </div>
      </footer>
    </div>
  );
}
