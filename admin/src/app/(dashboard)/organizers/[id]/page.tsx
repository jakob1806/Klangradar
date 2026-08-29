import { notFound } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { OrganizerForm } from "../organizer-form";
import { updateOrganizer } from "../actions";
export default async function OrganizerPage({params}:{params:Promise<{id:string}>}){const {id}=await params;const supabase=await createClient();const {data}=await supabase.from("organizers").select("name,slug,description_de,logo_url,website_url,contact_email").eq("id",id).maybeSingle();if(!data)notFound();return <div className="p-8"><h1 className="text-xl font-semibold tracking-tight">{data.name} bearbeiten</h1><p className="mt-1 text-sm text-neutral-500">Nur redaktionell verwaltbar; nicht in Endnutzer-Apps sichtbar.</p><div className="mt-6"><OrganizerForm initial={data} action={updateOrganizer.bind(null,id)}/></div></div>}
