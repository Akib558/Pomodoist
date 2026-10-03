begin;
select plan(1);

-- Standard PL/pgSQL assertions also run in an isolated in-memory PostgreSQL.
do $$
declare
  payload jsonb := '{"id":"ab900000-0000-4000-8000-000000000010","userId":"local-user","title":"Water","reminderMinutes":480,"scheduleHistory":[{"effectiveFrom":"2026-10-03","startDate":"2026-10-03","endDate":null,"weekdays":[1,2,3,4,5,6,7],"targetPerDay":7}],"createdAt":"2026-10-03T00:00:00Z","updatedAt":"2026-10-03T00:00:00Z","isDeleted":false}';
  candidate jsonb;
  period text;
  invalid jsonb;
begin
  -- Legacy payloads and every supported period are valid for full and partial writes.
  perform private.validate_pomodoist_habit_payload('habit',payload->>'id','ab900000-0000-4000-8000-000000000001',payload,false);
  foreach period in array array['automatic','anytime','morning','afternoon','evening','night'] loop
    candidate := jsonb_set(payload,'{scheduleHistory,0,dayPeriod}',to_jsonb(period));
    perform private.validate_pomodoist_habit_payload('habit',payload->>'id','ab900000-0000-4000-8000-000000000001',candidate,false);
    perform private.validate_pomodoist_habit_payload('habit',payload->>'id','ab900000-0000-4000-8000-000000000001',jsonb_build_object('scheduleHistory',candidate->'scheduleHistory'),true);
  end loop;
  foreach invalid in array array['"invalid"'::jsonb,'null'::jsonb,'7'::jsonb,'true'::jsonb,'[]'::jsonb,'{}'::jsonb] loop
    candidate := jsonb_set(payload,'{scheduleHistory,0,dayPeriod}',invalid);
    begin
      perform private.validate_pomodoist_habit_payload('habit',payload->>'id','ab900000-0000-4000-8000-000000000001',candidate,false);
      raise exception 'Expected invalid day period to fail: %',invalid;
    exception when sqlstate '22023' then
      if sqlerrm <> 'Invalid habit day period' then raise; end if;
    end;
    begin
      perform private.validate_pomodoist_habit_payload('habit',payload->>'id','ab900000-0000-4000-8000-000000000001',jsonb_build_object('scheduleHistory',candidate->'scheduleHistory'),true);
      raise exception 'Expected invalid partial day period to fail: %',invalid;
    exception when sqlstate '22023' then
      if sqlerrm <> 'Invalid habit day period' then raise; end if;
    end;
  end loop;
  -- Adding the allowed field must not weaken the schedule-key allowlist.
  begin
    perform private.validate_pomodoist_habit_payload('habit',payload->>'id','ab900000-0000-4000-8000-000000000001',jsonb_set(payload,'{scheduleHistory,0,unexpected}','true'),false);
    raise exception 'Expected an unknown schedule field to fail';
  exception when sqlstate '22023' then
    if sqlerrm <> 'Invalid habit schedule' then raise; end if;
  end;
end;
$$;
do $$
declare
  payload jsonb := '{"id":"ab900000-0000-4000-8000-000000000002","userId":"local-user","title":"Water","scheduleHistory":[{"effectiveFrom":"2026-10-03","startDate":"2026-10-03","endDate":null,"weekdays":[1,2,3,4,5,6,7],"targetPerDay":7}],"createdAt":"2026-10-03T09:00:00Z","updatedAt":"2026-10-03T09:00:00Z","isDeleted":false}';
  check_in jsonb := '{"id":"ab900000-0000-4000-8000-000000000003","userId":"local-user","habitId":"ab900000-0000-4000-8000-000000000002","day":"2026-10-03","createdAt":"2026-10-03T09:00:00Z","updatedAt":"2026-10-03T09:00:00Z","isDeleted":false}';
  candidate jsonb; value jsonb; partial boolean; period text;
begin
  candidate := jsonb_set(payload,'{scheduleHistory,0,periodTargets}','{"morning":2,"afternoon":2,"evening":2,"night":1}');
  foreach partial in array array[false,true] loop
    perform private.validate_pomodoist_habit_payload('habit',payload->>'id','ab900000-0000-4000-8000-000000000001',case when partial then jsonb_build_object('scheduleHistory',candidate->'scheduleHistory') else candidate end,partial);
  end loop;
  foreach value in array array['null'::jsonb,'[]'::jsonb,'{}'::jsonb,'7'::jsonb,'{"automatic":7}'::jsonb,'{"anytime":7}'::jsonb,'{"dawn":7}'::jsonb,'{"night":0}'::jsonb,'{"night":100}'::jsonb,'{"night":-1}'::jsonb,'{"night":1.5}'::jsonb,'{"night":"7"}'::jsonb,'{"night":null}'::jsonb,'{"night":true}'::jsonb,'{"night":6}'::jsonb,'{"night":7,"morning":1}'::jsonb] loop
    candidate := jsonb_set(payload,'{scheduleHistory,0,periodTargets}',value);
    foreach partial in array array[false,true] loop
      begin
        perform private.validate_pomodoist_habit_payload('habit',payload->>'id','ab900000-0000-4000-8000-000000000001',case when partial then jsonb_build_object('scheduleHistory',candidate->'scheduleHistory') else candidate end,partial);
        raise exception 'Expected period targets to fail: %',value;
      exception when sqlstate '22023' then
        if sqlerrm <> 'Invalid habit period targets' then raise; end if;
      end;
    end loop;
  end loop;
  candidate := jsonb_set(jsonb_set(payload,'{scheduleHistory,0,periodTargets}','{"night":7}'),'{scheduleHistory,0,dayPeriod}','"night"');
  begin
    perform private.validate_pomodoist_habit_payload('habit',payload->>'id','ab900000-0000-4000-8000-000000000001',candidate,false);
    raise exception 'Expected contradictory grouping to fail';
  exception when sqlstate '22023' then
    if sqlerrm <> 'Invalid habit period targets' then raise; end if;
  end;
  perform private.validate_pomodoist_habit_payload('habit_check_in',check_in->>'id','ab900000-0000-4000-8000-000000000001',check_in,false);
  foreach period in array array['anytime','morning','afternoon','evening','night'] loop
    foreach partial in array array[false,true] loop
      candidate := case when partial then jsonb_build_object('dayPeriod',period) else check_in || jsonb_build_object('dayPeriod',period) end;
      perform private.validate_pomodoist_habit_payload('habit_check_in',check_in->>'id','ab900000-0000-4000-8000-000000000001',candidate,partial);
    end loop;
  end loop;
  foreach value in array array['"automatic"'::jsonb,'"invalid"'::jsonb,'null'::jsonb,'7'::jsonb,'true'::jsonb,'[]'::jsonb,'{}'::jsonb] loop
    foreach partial in array array[false,true] loop
      candidate := case when partial then jsonb_build_object('dayPeriod',value) else check_in || jsonb_build_object('dayPeriod',value) end;
      begin
        perform private.validate_pomodoist_habit_payload('habit_check_in',check_in->>'id','ab900000-0000-4000-8000-000000000001',candidate,partial);
        raise exception 'Expected check-in period to fail: %',value;
      exception when sqlstate '22023' then
        if sqlerrm <> 'Invalid check-in day period' then raise; end if;
      end;
    end loop;
  end loop;
end;
$$;
select pass('legacy schedules and typed day periods pass full/partial validation; invalid fields are rejected');
select * from finish();
rollback;
