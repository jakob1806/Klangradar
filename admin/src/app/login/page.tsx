"use client";

import { Suspense, useState, type FormEvent } from "react";
import Image from "next/image";
import { useRouter, useSearchParams } from "next/navigation";
import { createClient } from "@/lib/supabase/client";

// Zweistufiger Login (E-Mail -> Code) statt reinem Magic-Link-Klick: das
// Magic-Link-E-Mail-Template ist projektweit dasselbe wie für die Flutter-
// App (siehe backend Supabase-Auth-Konfiguration), die dort bewusst nur den
// {{ .Token }}-Code anzeigt, keinen Link — ein Admin, der eine E-Mail vor
// einer Template-Anpassung bekommt (oder falls Änderungen am Mailer erst
// verzögert greifen), bekäme sonst nur einen Code, den es nirgends
// einzugeben gibt. verifyOtp() mit dem Code funktioniert unabhängig vom
// E-Mail-Template-Inhalt, weil der Code IMMER Teil der Antwort ist,
// unabhängig davon, ob die Mail zusätzlich einen Link zeigt.
function LoginForm() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const redirectTo = searchParams.get("redirectTo") ?? "/events";

  const [step, setStep] = useState<"email" | "code">("email");
  const [email, setEmail] = useState("");
  const [code, setCode] = useState("");
  const [status, setStatus] = useState<"idle" | "sending" | "verifying" | "error">("idle");
  const [errorMessage, setErrorMessage] = useState("");

  async function handleSendCode(event: FormEvent) {
    event.preventDefault();
    setStatus("sending");
    setErrorMessage("");

    const supabase = createClient();
    const { error } = await supabase.auth.signInWithOtp({ email });

    if (error) {
      setStatus("error");
      setErrorMessage(error.message);
      return;
    }
    setStatus("idle");
    setStep("code");
  }

  async function handleVerifyCode(event: FormEvent) {
    event.preventDefault();
    setStatus("verifying");
    setErrorMessage("");

    const supabase = createClient();
    const { error } = await supabase.auth.verifyOtp({
      email,
      token: code,
      type: "email",
    });

    if (error) {
      setStatus("error");
      setErrorMessage(error.message);
      return;
    }
    router.push(redirectTo);
    router.refresh();
  }

  return (
    <div className="admin-login-shell flex min-h-full items-center justify-center px-6 py-16">
      <div className="admin-login-card w-full max-w-sm">
        <div className="mb-7 text-center">
          <span className="dashboard-brand-mark mx-auto mb-3" aria-hidden="true">
            <Image src="/app-logo.svg" alt="" width={40} height={40} priority />
          </span>
          <p className="text-lg font-semibold tracking-tight">Klangradar</p>
          <p className="mt-0.5 text-xs text-neutral-500">Redaktions-Dashboard</p>
        </div>

        {step === "email" ? (
          <form onSubmit={handleSendCode} className="flex flex-col gap-3">
            <label className="text-xs font-medium text-neutral-600" htmlFor="email">
              E-Mail-Adresse
            </label>
            <input
              id="email"
              type="email"
              required
              autoFocus
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              placeholder="name@beispiel.de"
              className="rounded-md border border-neutral-300 px-3 py-2 text-sm outline-none focus:border-neutral-500"
            />
            {status === "error" && <p className="text-xs text-red-600">{errorMessage}</p>}
            <button
              type="submit"
              disabled={status === "sending"}
              className="mt-2 rounded-md bg-neutral-900 px-3 py-2 text-sm font-medium text-white hover:bg-neutral-700 disabled:opacity-50"
            >
              {status === "sending" ? "Sende Code…" : "Code senden"}
            </button>
            <p className="mt-1 text-center text-xs text-neutral-400">
              Kein Passwort nötig — du bekommst einen Code per E-Mail.
            </p>
          </form>
        ) : (
          <form onSubmit={handleVerifyCode} className="flex flex-col gap-3">
            <p className="text-xs text-neutral-500">
              Code geschickt an <span className="font-medium">{email}</span>.
            </p>
            <label className="text-xs font-medium text-neutral-600" htmlFor="code">
              Code aus der E-Mail
            </label>
            <input
              id="code"
              type="text"
              inputMode="numeric"
              required
              autoFocus
              value={code}
              onChange={(e) => setCode(e.target.value)}
              placeholder="123456"
              className="rounded-md border border-neutral-300 px-3 py-2 text-center text-lg font-semibold tracking-widest outline-none focus:border-neutral-500"
            />
            {status === "error" && <p className="text-xs text-red-600">{errorMessage}</p>}
            <button
              type="submit"
              disabled={status === "verifying"}
              className="mt-2 rounded-md bg-neutral-900 px-3 py-2 text-sm font-medium text-white hover:bg-neutral-700 disabled:opacity-50"
            >
              {status === "verifying" ? "Prüfe…" : "Anmelden"}
            </button>
            <button
              type="button"
              onClick={() => {
                setStep("email");
                setCode("");
                setStatus("idle");
                setErrorMessage("");
              }}
              className="text-center text-xs text-neutral-400 hover:text-neutral-600"
            >
              Andere E-Mail-Adresse verwenden
            </button>
          </form>
        )}
      </div>
    </div>
  );
}

export default function LoginPage() {
  return (
    <Suspense>
      <LoginForm />
    </Suspense>
  );
}
