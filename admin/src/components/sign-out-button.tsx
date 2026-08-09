"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";
import { createClient } from "@/lib/supabase/client";

export function SignOutButton() {
  const router = useRouter();
  const [pending, setPending] = useState(false);

  async function handleSignOut() {
    setPending(true);
    const supabase = createClient();
    await supabase.auth.signOut();
    router.push("/login");
    router.refresh();
  }

  return (
    <button
      onClick={handleSignOut}
      disabled={pending}
      className="text-[13px] font-medium text-[#0071e3] transition-colors hover:text-[#0077ed] disabled:opacity-50"
    >
      {pending ? "Abmelden…" : "Abmelden"}
    </button>
  );
}
