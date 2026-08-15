-- Ein einzelner historischer Base64-Import besitzt naturgemäß keine
-- externe Fundseite. Trotzdem muss die Herkunft als eingebetteter
-- Altbestand erkennbar sein und darf nicht namenlos bleiben.
update images
set source_name = 'Eingebettetes Bild (Altbestand)'
where source_name is null
  and source_url like 'data:image/%';

create or replace function ensure_image_source_provenance()
returns trigger
language plpgsql
as $$
begin
  if new.source_page_url is null and new.source_url ~* '^https?://' then
    new.source_page_url := new.source_url;
  end if;
  if new.source_name is null and new.source_page_url ~* '^https?://' then
    new.source_name := lower(
      regexp_replace(new.source_page_url, '^https?://([^/:?#]+).*$','\1', 'i')
    );
  end if;
  if new.source_name is null and new.source_url like 'manual-upload:%' then
    new.source_name := 'Manueller Upload';
  end if;
  if new.source_name is null and new.source_url like 'data:image/%' then
    new.source_name := 'Eingebettetes Bild';
  end if;
  return new;
end;
$$;
