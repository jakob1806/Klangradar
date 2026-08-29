"use client";

import { useState } from "react";
import { saveAvatarCrop } from "@/lib/gallery-actions";
import { CropTool } from "./crop-tool";
import { CroppedImagePreview } from "./cropped-image-preview";
import type { CropRect } from "./crop-math";

/** Nutzervorgabe: beim Festlegen eines Profilfotos soll die Redakteurin
 * bestimmen können, welcher Bildbereich im runden Avatar-Ausschnitt
 * (Personen-/Ensemble-Miniaturbild in Suche/Verzeichnis) sichtbar ist,
 * statt sich auf das automatische zentrierte BoxFit.cover zu verlassen.
 * Wiederverwendet den generalisierten CropTool (aspect=1, shape="circle")
 * mit der neuen persons/ensembles.avatar_crop_x/y/width/height-Spalte
 * statt der bestehenden 16:9-Galerie-Crops. Nur auf Bearbeiten-Seiten
 * sichtbar (braucht eine bereits existierende entityId) und nur aktiv,
 * solange ein Foto gesetzt ist. */
export function AvatarCropButton({
  entityType,
  entityId,
  photoUrl,
  initialCrop,
  path,
}: {
  entityType: "persons" | "ensembles" | "venues";
  entityId: string;
  photoUrl: string | null;
  initialCrop: CropRect | null;
  path: string;
}) {
  const [open, setOpen] = useState(false);

  if (!photoUrl) return null;

  return (
    <div className="flex items-center gap-3">
      <CroppedImagePreview
        src={photoUrl}
        crop={initialCrop}
        aspect={1}
        shape="circle"
        className="h-14 w-14 flex-none"
      />
      <button
        type="button"
        onClick={() => setOpen(true)}
        className="rounded-lg border border-black/10 bg-white px-3 py-1.5 text-xs font-medium text-neutral-700 hover:bg-black/[0.04]"
      >
        Ausschnitt festlegen
      </button>

      {open && (
        <CropTool
          src={photoUrl}
          initialCrop={initialCrop}
          aspect={1}
          shape="circle"
          title="Rundes Profilfoto: Ausschnitt festlegen"
          onSave={(crop) => saveAvatarCrop(entityType, entityId, crop, path)}
          onReset={() => saveAvatarCrop(entityType, entityId, null, path)}
          onClose={() => setOpen(false)}
        />
      )}
    </div>
  );
}
