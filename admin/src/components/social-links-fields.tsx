"use client";

import { useMemo, useState } from "react";
import { Field, TextInput } from "@/components/form-fields";

const PLATFORMS = [
  ["instagram", "Instagram", "https://www.instagram.com/profil"],
  ["facebook", "Facebook", "https://www.facebook.com/profil"],
  ["youtube", "YouTube", "https://www.youtube.com/@kanal"],
  ["spotify", "Spotify", "https://open.spotify.com/artist/…"],
  ["tiktok", "TikTok", "https://www.tiktok.com/@profil"],
  ["linkedin", "LinkedIn", "https://www.linkedin.com/company/profil"],
] as const;

export function SocialLinksFields({ initial = {} }: { initial?: Record<string, string> | null }) {
  const [links, setLinks] = useState<Record<string, string>>(initial ?? {});
  const value = useMemo(
    () => Object.fromEntries(Object.entries(links).filter(([, url]) => url.trim())),
    [links],
  );

  return (
    <fieldset className="space-y-3 rounded-xl border border-black/[0.08] bg-neutral-50 p-4">
      <legend className="px-1 text-sm font-medium text-neutral-900">Social Media</legend>
      <p className="text-xs text-neutral-500">Nur vollständige Profil-Links eintragen. Sie erscheinen als anklickbare Plattform-Links in den Apps.</p>
      <input type="hidden" name="social_links" value={JSON.stringify(value)} />
      <div className="grid gap-3 sm:grid-cols-2">
        {PLATFORMS.map(([key, label, placeholder]) => (
          <Field key={key} label={label}>
            <TextInput
              type="url"
              value={links[key] ?? ""}
              placeholder={placeholder}
              onChange={(event) => setLinks((current) => ({ ...current, [key]: event.target.value }))}
            />
          </Field>
        ))}
      </div>
    </fieldset>
  );
}
