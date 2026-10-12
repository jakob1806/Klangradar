// Sofortiges Feedback beim Seitenwechsel im Redaktions-Dashboard.
export default function Loading() {
  return (
    <div className="animate-pulse p-8" aria-busy="true" aria-label="Seite wird geladen">
      <div className="h-7 w-56 rounded-xl bg-[#18181B]/[0.08]" />
      <div className="mt-3 h-4 w-80 max-w-full rounded-full bg-[#18181B]/[0.06]" />
      <div className="mt-8 h-10 w-full rounded-xl bg-white" />
      <div className="mt-4 flex flex-col gap-2">
        {Array.from({ length: 8 }).map((_, i) => <div key={i} className="h-12 rounded-xl bg-white" />)}
      </div>
    </div>
  );
}
