do $$
declare
  v_id uuid;
begin
  insert into event_participants (event_id, person_id, role, display_order)
  values ('8c29aa20-ff34-4957-b7b9-adeab3020e0b', 'd59415af-7dae-4eec-81c0-d4d87fabba96', 'dirigent', 99)
  returning id into v_id;
  raise notice 'inserted %', v_id;
exception when others then
  raise notice 'FAILED: % (%)', sqlerrm, sqlstate;
end $$;
