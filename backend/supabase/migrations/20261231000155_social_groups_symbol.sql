-- Erstellt von Claude Code (07.11.2026): Gruppen bekommen statt Emojis
-- schlichte Symbole, gespeichert als "sf:<SF-Symbol-Name>" (z. B.
-- "sf:music.note"). Dafür reicht die alte Grenze von 4 Zeichen nicht.
alter table public.social_groups drop constraint if exists social_groups_emoji_check;
alter table public.social_groups
  add constraint social_groups_emoji_check check (emoji is null or char_length(emoji) <= 40);
