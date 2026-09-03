import Link from "next/link";

export default function NotFound() {
  return <main className="apple-font grid min-h-screen place-items-center px-6 text-center"><div><p className="type-label">404</p><h1 className="type-heading mt-3 text-4xl text-[#1d1d1f]">Diese Seite gibt es nicht.</h1><p className="mt-3 text-[#48484a]">Vielleicht wurde sie verschoben oder die Adresse ist nicht korrekt.</p><Link href="/" className="mt-7 inline-flex rounded-full bg-[#0071e3] px-5 py-3 text-sm font-semibold text-white">Zur Startseite</Link></div></main>;
}
