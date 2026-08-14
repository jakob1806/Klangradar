import Image from "next/image";

/** Miniaturansicht für Listen (Personen/Ensembles/Venues/Veranstaltungen) —
 * zeigt neben dem ImageStatusBadge direkt das Bild statt nur "Bild vorhanden". */
export function ListThumbnail({
  src,
  alt,
  rounded = false,
}: {
  src: string | null;
  alt: string;
  rounded?: boolean;
}) {
  if (!src) {
    return (
      <div
        className={`flex h-10 w-10 shrink-0 items-center justify-center bg-neutral-100 text-neutral-300 ${
          rounded ? "rounded-full" : "rounded-md"
        }`}
      >
        <svg viewBox="0 0 24 24" className="h-4 w-4" fill="none" stroke="currentColor" strokeWidth="1.5">
          <rect x="3" y="3" width="18" height="18" rx="2" />
          <circle cx="9" cy="9" r="1.5" />
          <path d="M21 15l-5-5-11 11" />
        </svg>
      </div>
    );
  }

  return (
    <Image
      src={src}
      alt={alt}
      width={40}
      height={40}
      unoptimized
      className={`h-10 w-10 shrink-0 object-cover ${rounded ? "rounded-full" : "rounded-md"}`}
    />
  );
}
