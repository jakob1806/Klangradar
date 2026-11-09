import type { Metadata } from "next";
import { LegalPage } from "@/components/legal-page";
import { IMPRESSUM } from "@/lib/legal-texts";

export const metadata: Metadata = { title: "Impressum", alternates: { canonical: "/impressum" } };

export default function Page() {
  return <LegalPage title="Impressum" sections={IMPRESSUM} />;
}
