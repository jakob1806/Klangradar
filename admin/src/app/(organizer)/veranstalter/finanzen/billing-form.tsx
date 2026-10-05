"use client";

import { useState, useTransition } from "react";
import { Button } from "@/components/organizer/ui/button";
import { Input } from "@/components/organizer/ui/input";
import { Label } from "@/components/organizer/ui/label";
import { saveBillingProfile } from "./billing-actions";

export type BillingProfile = { name: string; street: string; zip: string; city: string; country: string; vat_id: string | null };

export function BillingForm({ initial }: { initial: BillingProfile | null }) {
  const [pending, start] = useTransition();
  const [message, setMessage] = useState<{ error?: string; ok?: boolean } | null>(null);

  return (
    <form
      className="grid gap-3 sm:grid-cols-2"
      action={(formData) =>
        start(async () => {
          const result = await saveBillingProfile(formData);
          setMessage(result.error ? { error: result.error } : { ok: true });
        })
      }
    >
      <div className="sm:col-span-2">
        <Label htmlFor="bf-name">Name / Firma</Label>
        <Input id="bf-name" name="name" defaultValue={initial?.name ?? ""} required maxLength={200} />
      </div>
      <div className="sm:col-span-2">
        <Label htmlFor="bf-street">Straße und Hausnummer</Label>
        <Input id="bf-street" name="street" defaultValue={initial?.street ?? ""} required maxLength={200} />
      </div>
      <div>
        <Label htmlFor="bf-zip">PLZ</Label>
        <Input id="bf-zip" name="zip" defaultValue={initial?.zip ?? ""} required maxLength={20} />
      </div>
      <div>
        <Label htmlFor="bf-city">Ort</Label>
        <Input id="bf-city" name="city" defaultValue={initial?.city ?? ""} required maxLength={120} />
      </div>
      <div>
        <Label htmlFor="bf-country">Land</Label>
        <Input id="bf-country" name="country" defaultValue={initial?.country ?? "Deutschland"} maxLength={80} />
      </div>
      <div>
        <Label htmlFor="bf-vat">USt-IdNr. (optional)</Label>
        <Input id="bf-vat" name="vat_id" defaultValue={initial?.vat_id ?? ""} maxLength={30} />
      </div>
      <div className="flex items-center gap-3 sm:col-span-2">
        <Button type="submit" disabled={pending}>{pending ? "Speichern …" : "Rechnungsanschrift speichern"}</Button>
        {message?.error && <p className="text-sm text-[#a12626]">{message.error}</p>}
        {message?.ok && <p className="text-sm text-[#2f6b3a]">Gespeichert.</p>}
      </div>
    </form>
  );
}
