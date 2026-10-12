// Sofortiges Feedback beim Seitenwechsel: ohne loading.tsx blieb die alte
// Seite stehen, bis der Server fertig war — das wirkte wie ein Aufhängen.
export default function Loading() {
  return (
    <div className="animate-pulse px-6 py-8 lg:px-10" aria-busy="true" aria-label="Seite wird geladen">
      <div className="h-3 w-24 rounded-full bg-[#18181B]/[0.07]" />
      <div className="mt-3 h-8 w-64 rounded-xl bg-[#18181B]/[0.08]" />
      <div className="mt-3 h-4 w-96 max-w-full rounded-full bg-[#18181B]/[0.06]" />
      <div className="mt-10 grid gap-4 sm:grid-cols-3">
        {[0, 1, 2].map((i) => <div key={i} className="h-28 rounded-2xl bg-white shadow-[0_1px_2px_rgba(24,24,27,0.04)]" />)}
      </div>
      <div className="mt-6 h-64 rounded-2xl bg-white shadow-[0_1px_2px_rgba(24,24,27,0.04)]" />
    </div>
  );
}
