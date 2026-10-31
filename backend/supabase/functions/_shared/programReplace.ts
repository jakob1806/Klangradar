// Erstellt von Claude Code (31.10.2026): Programm eines Termins als Ganzes
// ersetzen (statt löschen + einzeln einfügen). Die Datenbankfunktion
// replace_event_program entfernt doppelte Werke (gleiches Werk in derselben
// Programmhälfte), nummeriert neu und lässt redaktionell bearbeitete
// Programme (events.program_locked_at) unverändert.

export interface ProgramLink {
  work_id: string;
  position: number;
  after_intermission: boolean;
}

/** Anzahl geschriebener Werke (0, wenn das Programm gesperrt ist). */
// deno-lint-ignore no-explicit-any
export async function replaceProgram(supabase: any, eventId: string, links: ProgramLink[]): Promise<number> {
  if (links.length === 0) return 0;
  const { data, error } = await supabase.rpc("replace_event_program", { p_event_id: eventId, p_links: links });
  if (error) throw new Error(`replace_event_program: ${error.message}`);
  return data === true ? new Set(links.map((l) => `${l.work_id}|${l.after_intermission}`)).size : 0;
}
