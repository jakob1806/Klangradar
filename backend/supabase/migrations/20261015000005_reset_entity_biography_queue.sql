-- Wird eine Ensemble-/Venue-Beschreibung bewusst geleert, soll die
-- automatische Recherche wieder anlaufen statt am alten generated-Status
-- hängen zu bleiben.
create or replace function public.reset_entity_ai_biography_queue()
returns trigger language plpgsql set search_path = public as $$
begin
  if nullif(btrim(old.description_de), '') is not null
     and nullif(btrim(new.description_de), '') is null then
    new.ai_biography_status := 'pending';
    new.ai_biography_checked_at := null;
    new.ai_biography_error := null;
  end if;
  return new;
end; $$;

drop trigger if exists ensembles_reset_ai_biography_queue on public.ensembles;
create trigger ensembles_reset_ai_biography_queue before update of description_de on public.ensembles
for each row execute function public.reset_entity_ai_biography_queue();

drop trigger if exists venues_reset_ai_biography_queue on public.venues;
create trigger venues_reset_ai_biography_queue before update of description_de on public.venues
for each row execute function public.reset_entity_ai_biography_queue();
