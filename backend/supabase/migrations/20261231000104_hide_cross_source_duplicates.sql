-- Erstellt von Claude Code (23.10.2026, Nutzermeldung: "viele Konzert-Duplikate,
-- v. a. BRSO und MPhil"). Ursache: Aggregatoren (in-muenchen, concerti,
-- gasteig.de, ...) liefern dasselbe Konzert wie die offizielle Quelle, aber mit
-- anderem Titel ("BRSO: Young, Hadelich – ..." vs. "Symphonieorchester des
-- Bayerischen Rundfunks: Simone Young & ..."), daher greift der Abgleich in
-- ingest-source nicht.
--
-- Regel: verschiedene Quellen, gleicher Saal, Beginn ±15 Min. und entweder
-- gemeinsame aussagekräftige Titelwörter (2, bei sehr kurzen Titeln 1) oder
-- mindestens eine gemeinsame mitwirkende Person/Ensemble. Behalten wird der
-- Termin mit mehr Programm/Besetzung, bei Gleichstand der ältere. Der andere
-- wird als abgelehnter Entwurf ausgeblendet (nicht gelöscht); ingest-source
-- veröffentlicht Entwürfe anderer Quellen nicht wieder.
-- Vorab gegen Live-Daten simuliert: 8 Treffer über Titel, alle echte Dubletten.

create or replace function event_title_tokens(p_title text)
returns text[] language sql immutable as $$
  select coalesce(array_agg(distinct w), '{}')
  from regexp_split_to_table(lower(coalesce(p_title, '')), '[^[:alpha:]]+') w
  where length(w) >= 4
    and w not in ('konzert', 'konzerte', 'orchester', 'münchner', 'muenchner', 'bayerischen',
                  'rundfunks', 'symphonieorchester', 'philharmoniker', 'werke', 'live', 'abend',
                  'sinfoniekonzert', 'abonnementkonzert', 'saal', 'münchen', 'muenchen',
                  'premiere', 'with')
$$;

create or replace function hide_cross_source_duplicates()
returns int language plpgsql security definer set search_path = public as $$
declare
  v_hidden int;
begin
  with candidates as (
    select e.id, e.source_id, e.venue_id, e.start_datetime, e.created_at,
           event_title_tokens(e.title) as tokens,
           (select count(*) from event_works w where w.event_id = e.id)
             + (select count(*) from event_participants p where p.event_id = e.id) as richness
    from events e
    where e.status in ('scheduled', 'sold_out')
      and e.start_datetime >= now() - interval '1 day'
      and e.venue_id is not null
  ),
  pairs as (
    select a.id as keep_id, b.id as drop_id
    from candidates a
    join candidates b
      on b.venue_id = a.venue_id
     and b.id <> a.id
     and b.source_id is distinct from a.source_id
     and abs(extract(epoch from (b.start_datetime - a.start_datetime))) <= 900
    where (a.richness, b.created_at, b.id::text) > (b.richness, a.created_at, a.id::text)
      and (
        (cardinality(a.tokens) > 0 and cardinality(b.tokens) > 0
         and (select count(*) from unnest(a.tokens) t where t = any(b.tokens))
             >= least(2, greatest(1, least(cardinality(a.tokens), cardinality(b.tokens)) - 1)))
        or exists (
          select 1 from event_participants pa
          join event_participants pb
            on pb.event_id = b.id
           and (pb.person_id = pa.person_id or pb.ensemble_id = pa.ensemble_id)
          where pa.event_id = a.id
        )
      )
  )
  update events e
  set status = 'draft', review_status = 'rejected', updated_at = now()
  where e.id in (select drop_id from pairs)
    -- Ketten (A behält B, B behält C) nicht doppelt auflösen: wer selbst
    -- ausgeblendet wird, schützt niemanden.
    and e.id not in (select keep_id from pairs where keep_id not in (select drop_id from pairs));
  get diagnostics v_hidden = row_count;
  return v_hidden;
end;
$$;

revoke all on function hide_cross_source_duplicates() from public, anon, authenticated;

select hide_cross_source_duplicates();

select cron.unschedule('hide-cross-source-duplicates')
where exists (select 1 from cron.job where jobname = 'hide-cross-source-duplicates');
select cron.schedule('hide-cross-source-duplicates', '7,37 * * * *', $$ select hide_cross_source_duplicates(); $$);
