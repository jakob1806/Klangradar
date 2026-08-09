import type { InputHTMLAttributes, SelectHTMLAttributes, TextareaHTMLAttributes } from "react";

// Swiss/International-Redesign: eckig statt abgerundet, schwarzer statt
// grauer Fokus-Rand — dieselben zwei Klassen werden von JEDEM Formular im
// Dashboard über Field/TextInput/TextArea/Select bezogen, ändern hier
// wirkt daher konsistent auf alle Bearbeiten-Seiten gleichzeitig.
const labelClass = "type-label !text-neutral-600";
const controlClass = "border border-neutral-300 px-3 py-2 text-sm outline-none focus:border-[#171717]";

export function Field({
  label,
  required,
  hint,
  children,
}: {
  label: string;
  required?: boolean;
  hint?: string;
  children: React.ReactNode;
}) {
  return (
    <label className="flex flex-col gap-1.5">
      <span className={labelClass}>
        {label}
        {required && <span className="text-red-500"> *</span>}
      </span>
      {children}
      {hint && <span className="text-xs text-neutral-400">{hint}</span>}
    </label>
  );
}

export function TextInput(props: InputHTMLAttributes<HTMLInputElement>) {
  return <input {...props} className={`${controlClass} ${props.className ?? ""}`} />;
}

export function TextArea(props: TextareaHTMLAttributes<HTMLTextAreaElement>) {
  return <textarea {...props} className={`${controlClass} ${props.className ?? ""}`} />;
}

export function Select(props: SelectHTMLAttributes<HTMLSelectElement>) {
  return <select {...props} className={`${controlClass} bg-white ${props.className ?? ""}`} />;
}
