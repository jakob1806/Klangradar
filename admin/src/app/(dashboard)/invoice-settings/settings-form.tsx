"use client";

import { useActionState } from "react";
import { Field, TextInput } from "@/components/form-fields";
import { saveInvoiceSettings } from "./actions";

export type InvoiceSettings = {
  issuer_name: string; issuer_street: string; issuer_zip: string; issuer_city: string; issuer_country: string;
  tax_number: string | null; vat_id: string | null; iban: string | null; bic: string | null;
  email: string | null; phone: string | null; small_business: boolean; vat_rate: number;
};

export function InvoiceSettingsForm({ settings }: { settings: InvoiceSettings }) {
  const [state, action, pending] = useActionState(saveInvoiceSettings, {});
  return (
    <form action={action} className="grid max-w-3xl gap-4 sm:grid-cols-2">
      <div className="sm:col-span-2"><Field label="Name / Firma" required><TextInput name="issuer_name" defaultValue={settings.issuer_name} required /></Field></div>
      <div className="sm:col-span-2"><Field label="Straße und Hausnummer" required><TextInput name="issuer_street" defaultValue={settings.issuer_street} required /></Field></div>
      <Field label="PLZ" required><TextInput name="issuer_zip" defaultValue={settings.issuer_zip} required /></Field>
      <Field label="Ort" required><TextInput name="issuer_city" defaultValue={settings.issuer_city} required /></Field>
      <Field label="Land"><TextInput name="issuer_country" defaultValue={settings.issuer_country} /></Field>
      <Field label="E-Mail"><TextInput name="email" type="email" defaultValue={settings.email ?? ""} /></Field>
      <Field label="Steuernummer" hint="Steuernummer oder USt-IdNr. ist Pflicht für Rechnungen."><TextInput name="tax_number" defaultValue={settings.tax_number ?? ""} /></Field>
      <Field label="USt-IdNr."><TextInput name="vat_id" defaultValue={settings.vat_id ?? ""} /></Field>
      <Field label="IBAN" required><TextInput name="iban" defaultValue={settings.iban ?? ""} /></Field>
      <Field label="BIC"><TextInput name="bic" defaultValue={settings.bic ?? ""} /></Field>
      <Field label="Telefon"><TextInput name="phone" defaultValue={settings.phone ?? ""} /></Field>
      <Field label="USt-Satz in %"><TextInput name="vat_rate" inputMode="decimal" defaultValue={String(settings.vat_rate)} /></Field>
      <label className="flex items-center gap-2 text-sm sm:col-span-2">
        <input type="checkbox" name="small_business" defaultChecked={settings.small_business} />
        Kleinunternehmer nach § 19 UStG (keine Umsatzsteuer ausweisen)
      </label>
      <div className="flex items-center gap-3 sm:col-span-2">
        <button disabled={pending} className="rounded-full bg-neutral-900 px-5 py-2 text-sm font-semibold text-white disabled:opacity-50">{pending ? "Speichern …" : "Speichern"}</button>
        {state.error && <p className="text-sm text-red-700">{state.error}</p>}
        {state.ok && <p className="text-sm text-emerald-700">Gespeichert. Neue Rechnungen verwenden diese Angaben.</p>}
      </div>
    </form>
  );
}
