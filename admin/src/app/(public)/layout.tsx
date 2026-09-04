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
    <div className="apple-font flex min-h-screen flex-col">
      <header className="sticky top-0 z-10 flex items-center justify-between border-b border-black/5 bg-white/70 px-6 py-3.5 backdrop-blur-xl">
        <Link href="/" className="flex items-center gap-2.5">
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
            href={cta.href}
            className="rounded-full bg-[#0071e3] px-4 py-2 text-sm font-semibold text-white transition hover:bg-[#0077ed] active:scale-[0.985]"
          >
            {cta.label}
          </Link>
        </div>
      </header>

      <main className="flex-1">{children}</main>

      <footer className="flex items-center justify-center gap-6 px-6 py-8 text-xs text-[#86868b]">
        <Link href="/impressum" className="hover:text-[#1d1d1f]">
          Impressum
        </Link>
        <Link href="/datenschutz" className="hover:text-[#1d1d1f]">
          Datenschutz
        </Link>
        <Link href="/nutzungsbedingungen" className="hover:text-[#1d1d1f]">
          Nutzungsbedingungen
        </Link>
      </footer>
    </div>
  );
}
