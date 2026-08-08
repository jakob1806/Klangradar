"use client";

import { ConfirmButton } from "./confirm-button";

// War früher eine eigenständige window.confirm()-Implementierung ohne
// jede Fehlerbehandlung — ein fehlgeschlagener Löschversuch (z.B. Fremd-
// schlüssel-Verletzung, weil noch Veranstaltungen/Quellen auf die Entität
// verweisen) verschwand als unbehandelte Promise-Rejection, für die
// Redaktion sah das aus wie "Löschen tut gar nichts" (Nutzerfeedback:
// "ensembles löschen klappt nicht"). ConfirmButton löst genau das schon
// (siehe dessen Kommentar) — DeleteButton ist jetzt nur noch ein dünner
// Wrapper mit dem roten "Löschen"-Styling, damit alle bisherigen Aufrufer
// unverändert bleiben können.
export function DeleteButton({
  action,
  confirmMessage,
}: {
  action: () => Promise<void>;
  confirmMessage: string;
}) {
  return (
    <ConfirmButton
      action={action}
      confirmMessage={confirmMessage}
      label="Löschen"
      pendingLabel="Lösche…"
      className="text-sm font-medium text-red-600 hover:text-red-800 disabled:opacity-50"
    />
  );
}
