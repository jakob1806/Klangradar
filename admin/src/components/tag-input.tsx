"use client";

import { useState } from "react";

/** Freies Mehrfachwert-Feld (z.B. persons.roles) statt einer festen
 * Checkbox-Liste — Nutzervorgabe: "dort sollen auch Sachen wie Schauspieler,
 * Regisseur, nicht nur Komponist usw. drinstehen [...] keine Checkboxen zur
 * Auswahl sondern alle Begriffe gehen". Schreibt die Werte kommagetrennt in
 * ein verstecktes Feld, das die umgebende <form action> wie jedes normale
 * Textfeld liest. `suggestions` sind nur Schnellauswahl-Chips, keine
 * Einschränkung der möglichen Werte. */
export function TagInput({
  name,
  defaultValue,
  suggestions = [],
  placeholder,
}: {
  name: string;
  defaultValue: string[];
  suggestions?: { value: string; label: string }[];
  placeholder?: string;
}) {
  const [tags, setTags] = useState<string[]>(defaultValue);
  const [draft, setDraft] = useState("");

  function addTag(raw: string) {
    const value = raw.trim().toLocaleLowerCase("de");
    if (!value || tags.includes(value)) return;
    setTags((current) => [...current, value]);
  }

  function removeTag(value: string) {
    setTags((current) => current.filter((tag) => tag !== value));
  }

  function handleKeyDown(e: React.KeyboardEvent<HTMLInputElement>) {
    if (e.key === "Enter" || e.key === ",") {
      e.preventDefault();
      addTag(draft);
      setDraft("");
    } else if (e.key === "Backspace" && draft === "" && tags.length > 0) {
      removeTag(tags[tags.length - 1]);
    }
  }

  const remainingSuggestions = suggestions.filter((s) => !tags.includes(s.value));

  return (
    <div className="flex flex-col gap-2">
      <input type="hidden" name={name} value={tags.join(",")} />
      <div className="flex flex-wrap items-center gap-1.5 border border-neutral-300 px-2 py-1.5">
        {tags.map((tag) => (
          <span
            key={tag}
            className="flex items-center gap-1 rounded-full bg-neutral-100 px-2.5 py-1 text-xs text-neutral-700"
          >
            {tag}
            <button
              type="button"
              onClick={() => removeTag(tag)}
              className="text-neutral-400 hover:text-neutral-800"
              aria-label={`${tag} entfernen`}
            >
              ×
            </button>
          </span>
        ))}
        <input
          type="text"
          value={draft}
          onChange={(e) => setDraft(e.target.value)}
          onKeyDown={handleKeyDown}
          onBlur={() => {
            if (draft.trim()) {
              addTag(draft);
              setDraft("");
            }
          }}
          placeholder={tags.length === 0 ? placeholder : undefined}
          className="min-w-[10ch] flex-1 border-none px-1 py-0.5 text-sm outline-none"
        />
      </div>
      {remainingSuggestions.length > 0 && (
        <div className="flex flex-wrap gap-1.5">
          {remainingSuggestions.map((s) => (
            <button
              key={s.value}
              type="button"
              onClick={() => addTag(s.value)}
              className="rounded-full border border-neutral-200 px-2.5 py-1 text-xs text-neutral-500 hover:border-neutral-400 hover:text-neutral-800"
            >
              + {s.label}
            </button>
          ))}
        </div>
      )}
    </div>
  );
}
