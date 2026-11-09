import type { Metadata } from "next";
import { LegalPage } from "@/components/legal-page";
import { AGB } from "@/lib/legal-texts";

export const metadata: Metadata = { title: "Nutzungsbedingungen", alternates: { canonical: "/nutzungsbedingungen" } };

export default function Page() {
  return <LegalPage title="Nutzungsbedingungen" sections={AGB} />;
}
