-- Jede webbasierte Bildzeile muss auch dann eine nachvollziehbare Quelle
-- behalten, wenn sie vor Einführung der vollständigen Provenienzfelder
-- importiert wurde. Die direkte Bild-URL ist für Altbestände die
-- bestmögliche rekonstruierbare Fundstelle; der Host wird als Anbieter
-- festgehalten. Neuere Importpfade liefern weiterhin die präzisere echte
-- Inhaltsseite und überschreiben diese Werte nicht.
update images
set source_page_url = source_url
where source_page_url is null
  and source_url ~* '^https?://';

update images
set source_name = lower(
  regexp_replace(source_page_url, '^https?://([^/:?#]+).*$','\1', 'i')
)
where source_name is null
  and source_page_url ~* '^https?://';

update images
set source_name = 'Manueller Upload'
where source_name is null
  and source_url like 'manual-upload:%';

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
  return new;
end;
$$;

drop trigger if exists images_ensure_source_provenance on images;
create trigger images_ensure_source_provenance
before insert or update of source_url, source_page_url, source_name on images
for each row execute function ensure_image_source_provenance();

comment on function ensure_image_source_provenance() is
  'Garantiert für Webbilder mindestens Fund-URL und Anbieterhost; präzisere Metadaten der Recherchepipeline bleiben unverändert.';
