"use server";

import { cookies } from "next/headers";
import { revalidatePath } from "next/cache";
import { CITY_FILTER_COOKIE } from "@/lib/city-filter";

export async function setCityFilter(slug: string) {
  const cookieStore = await cookies();
  // 1 Jahr — bewusst lang, das ist eine Redaktions-Arbeitsumgebungs-
  // Einstellung, kein sitzungsgebundener Zustand.
  cookieStore.set(CITY_FILTER_COOKIE, slug, { path: "/", maxAge: 60 * 60 * 24 * 365 });
  revalidatePath("/", "layout");
}
