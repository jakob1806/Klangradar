import type { Metadata } from "next";
import { LegalPage } from "@/components/legal-page";
import { DATENSCHUTZ } from "@/lib/legal-texts";

export const metadata: Metadata = { title: "Datenschutz", alternates: { canonical: "/datenschutz" } };

export default function Page() {
  return <LegalPage title="Datenschutzerklärung" sections={DATENSCHUTZ} />;
}
