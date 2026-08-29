"use server";
import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
function fields(formData: FormData) { return { name:String(formData.get("name")??"").trim(), slug:String(formData.get("slug")??"").trim(), description_de:String(formData.get("description_de")??"").trim()||null, logo_url:String(formData.get("logo_url")??"").trim()||null, website_url:String(formData.get("website_url")??"").trim()||null, contact_email:String(formData.get("contact_email")??"").trim()||null }; }
export async function createOrganizer(formData: FormData) { const supabase=await createClient(); const {error}=await supabase.from("organizers").insert(fields(formData)); if(error) throw new Error(error.message); revalidatePath("/organizers"); redirect("/organizers"); }
export async function updateOrganizer(id:string,formData:FormData) { const supabase=await createClient(); const {error}=await supabase.from("organizers").update(fields(formData)).eq("id",id); if(error) throw new Error(error.message); revalidatePath("/organizers"); redirect("/organizers"); }
