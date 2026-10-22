import type { Metadata } from "next";

// Einladungslink https://klangradar.com/f/<CODE>. Mit installierter App
// öffnet iOS direkt die App (Universal Link); sonst landet man hier.
// Erstellt von Claude Code.
export const metadata: Metadata = {
  title: "Einladung zu Klangradar",
  description: "Du wurdest zu Klangradar eingeladen – sieh, zu welchen Konzerten deine Freunde gehen.",
  robots: { index: false, follow: false },
};

export default async function FriendInvitePage({ params }: { params: Promise<{ code: string }> }) {
  const { code: raw } = await params;
  const code = raw.toUpperCase().replace(/[^A-Z0-9]/g, "").slice(0, 12);
  const appLink = `de.klangradar.native://friend/${code}`;
  return (
    <div className="mx-auto flex max-w-md flex-col items-center px-6 py-20 text-center">
      <div className="flex size-16 items-center justify-center rounded-2xl bg-[#146194]/10 text-3xl" aria-hidden>
        🎻
      </div>
      <h1 className="type-heading mt-6 text-3xl text-[#1d1d1f]">Du wurdest eingeladen</h1>
      <p className="mt-3 text-[15px] leading-relaxed text-[#3a3a3c]">
        Auf Klangradar seht ihr gegenseitig, zu welchen Konzerten ihr geht, plant Konzertabende gemeinsam und teilt eure Lieblingslisten.
      </p>
      <a
        href={appLink}
        className="mt-8 inline-flex h-12 w-full items-center justify-center rounded-full bg-[#146194] px-6 text-[15px] font-semibold text-white transition hover:bg-[#0f4c74]"
      >
        In Klangradar öffnen
      </a>
      <div className="mt-8 w-full rounded-2xl border border-black/10 bg-white p-5">
        <p className="text-[13px] text-[#86868b]">Noch keine App? Gib nach der Installation diesen Code unter Profil → Freunde ein:</p>
        <p className="mt-2 font-mono text-2xl font-semibold tracking-[0.2em] text-[#1d1d1f]">{code}</p>
      </div>
    </div>
  );
}
