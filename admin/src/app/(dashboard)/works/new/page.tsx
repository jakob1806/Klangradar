import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { createWork } from "../actions";
import { WorkForm } from "../work-form";

export default async function NewWorkPage() {
  const supabase = await createClient();
  const { data } = await supabase.from("persons").select("id, full_name").order("full_name").returns<{ id: string; full_name: string }[]>();
  return <div className="p-8"><Link href="/works" className="text-sm text-neutral-500 hover:text-neutral-800">← Zurück zu Werke</Link><h1 className="mt-3 text-xl font-semibold tracking-tight">Neues Werk anlegen</h1><div className="mt-7"><WorkForm action={createWork} persons={data ?? []} /></div></div>;
}
