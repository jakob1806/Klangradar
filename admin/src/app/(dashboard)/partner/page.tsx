import { createClient } from "@/lib/supabase/server";
import { createAffiliateRule, createPartnerOffer, toggleActive } from "./actions";

export const dynamic = "force-dynamic";

type Rule = { id: string; label: string; host_suffix: string; url_template: string | null; append_params: Record<string, string>; active: boolean };
type Offer = { id: string; partner_name: string; title: string; code: string | null; valid_until: string | null; active: boolean };

const input = "h-9 rounded-md border border-neutral-200 px-3 text-sm";

function ActiveToggle({ table, id, active }: { table: string; id: string; active: boolean }) {
  return (
    <form action={toggleActive}>
      <input type="hidden" name="table" value={table} />
      <input type="hidden" name="id" value={id} />
      <input type="hidden" name="active" value={String(!active)} />
      <button className={`rounded-full px-3 py-1 text-xs font-semibold ${active ? "bg-emerald-50 text-emerald-700" : "bg-neutral-100 text-neutral-500"}`}>{active ? "Aktiv" : "Inaktiv"}</button>
    </form>
  );
}

export default async function PartnerPage() {
  const supabase = await createClient();
  const [{ data: rules }, { data: offers }] = await Promise.all([
    supabase.from("affiliate_rules").select("id, label, host_suffix, url_template, append_params, active").order("created_at").returns<Rule[]>(),
    supabase.from("partner_offers").select("id, partner_name, title, code, valid_until, active").order("sort_order").returns<Offer[]>(),
  ]);

  return (
    <div className="flex max-w-4xl flex-col gap-12 p-8">
      <section>
        <h1 className="text-xl font-semibold tracking-tight">Affiliate-Links</h1>
        <p className="mt-1 text-sm text-neutral-500">
          Ticketlinks auf diesen Domains schreibt die iOS-App beim Öffnen um und kennzeichnet sie als „Partnerlink“. Erst eintragen, wenn das Partnerprogramm bestätigt ist.
        </p>
        <table className="mt-4 w-full text-sm">
          <tbody className="divide-y divide-neutral-100">
            {(rules ?? []).map((rule) => (
              <tr key={rule.id}>
                <td className="py-2 font-medium">{rule.label}</td>
                <td className="py-2 text-neutral-500">{rule.host_suffix}</td>
                <td className="max-w-xs truncate py-2 text-neutral-500">{rule.url_template ?? new URLSearchParams(rule.append_params).toString()}</td>
                <td className="py-2 text-right"><ActiveToggle table="affiliate_rules" id={rule.id} active={rule.active} /></td>
              </tr>
            ))}
          </tbody>
        </table>
        <form action={createAffiliateRule} className="mt-4 grid gap-2 sm:grid-cols-2">
          <input name="label" placeholder="Name, z. B. Eventim (Awin)" className={input} />
          <input name="host_suffix" required placeholder="Domain, z. B. eventim.de" className={input} />
          <input name="append_params" placeholder="Parameter, z. B. affiliate=KLR&utm_source=klangradar" className={input} />
          <input name="url_template" placeholder="oder Tracking-Link mit {url}" className={input} />
          <button className="h-9 rounded-md bg-neutral-900 px-4 text-sm font-medium text-white sm:col-span-2 sm:justify-self-start">Regel anlegen</button>
        </form>
      </section>

      <section>
        <h2 className="text-xl font-semibold tracking-tight">Plus-Partnervorteile</h2>
        <p className="mt-1 text-sm text-neutral-500">Erscheinen in der App unter Profil → Partner-Vorteile. Den Code sehen nur Plus-Mitglieder.</p>
        <table className="mt-4 w-full text-sm">
          <tbody className="divide-y divide-neutral-100">
            {(offers ?? []).map((offer) => (
              <tr key={offer.id}>
                <td className="py-2 font-medium">{offer.partner_name}</td>
                <td className="py-2">{offer.title}</td>
                <td className="py-2 font-mono text-neutral-500">{offer.code ?? "–"}</td>
                <td className="py-2 text-neutral-500">{offer.valid_until ?? "unbefristet"}</td>
                <td className="py-2 text-right"><ActiveToggle table="partner_offers" id={offer.id} active={offer.active} /></td>
              </tr>
            ))}
          </tbody>
        </table>
        <form action={createPartnerOffer} className="mt-4 grid gap-2 sm:grid-cols-2">
          <input name="partner_name" required placeholder="Partner, z. B. Café im Gasteig" className={input} />
          <input name="title" required placeholder="Vorteil, z. B. 10 % auf Getränke vor dem Konzert" className={input} />
          <input name="description" placeholder="Beschreibung (optional)" className={`${input} sm:col-span-2`} />
          <input name="code" placeholder="Gutscheincode (optional)" className={input} />
          <input name="url" type="url" placeholder="Link zum Partner (optional)" className={input} />
          <input name="valid_until" type="date" className={input} />
          <button className="h-9 rounded-md bg-neutral-900 px-4 text-sm font-medium text-white sm:justify-self-start">Vorteil anlegen</button>
        </form>
      </section>
    </div>
  );
}
