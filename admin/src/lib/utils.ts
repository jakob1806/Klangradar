import { type ClassValue, clsx } from "clsx";
import { twMerge } from "tailwind-merge";

/** shadcn-Standardhelfer: kombiniert bedingte Klassennamen und löst
 * widersprüchliche Tailwind-Utility-Klassen zugunsten der zuletzt
 * übergebenen auf (z.B. `cn("px-2", isWide && "px-4")` → "px-4"). */
export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}
