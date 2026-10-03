-- One consolidated Habits update: manual periods, per-period goals, check-in attribution and MCP access.
-- Deploy before the updated client; older payloads remain valid.
create or replace function private.validate_pomodoist_habit_payload(p_type text,p_id text,p_user_id uuid,p_data jsonb,p_partial boolean) returns void
language plpgsql set search_path = '' as $$
declare version jsonb; key text; weekdays jsonb; effective date; last_effective date; start_day date; end_day date; stamp text; quota record; quota_total numeric;
begin
  if p_type not in ('habit','habit_check_in') then return; end if;
  if p_id !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
    or ((not p_partial or p_data ? 'id') and p_data->>'id' is distinct from p_id)
    or pg_catalog.jsonb_typeof(p_data) is distinct from 'object'
    or ((not p_partial or p_data ? 'userId') and (p_data->>'userId' not in ('local-user',p_user_id::text) or p_data->>'userId' is null))
    or ((not p_partial or p_data ? 'isDeleted') and (pg_catalog.jsonb_typeof(p_data->'isDeleted') is distinct from 'boolean' or p_data->>'isDeleted' <> 'false')) then
    raise exception using errcode='22023', message='Invalid habit identity';
  end if;
  for key in select pg_catalog.jsonb_object_keys(p_data) loop
    if not (key = any(case p_type when 'habit' then array['id','userId','title','projectId','reminderMinutes','scheduleHistory','createdAt','updatedAt','isDeleted']
      else array['id','userId','habitId','day','createdAt','updatedAt','isDeleted','dayPeriod'] end)) then
      raise exception using errcode='22023', message='Invalid habit field';
    end if;
  end loop;
  foreach key in array array['createdAt','updatedAt'] loop
    if p_partial and not (p_data ? key) then continue; end if;
    stamp := p_data->>key;
    if pg_catalog.jsonb_typeof(p_data->key) is distinct from 'string' or stamp !~ '(Z|[+-][0-9]{2}:[0-9]{2})$' then
      raise exception using errcode='22023', message='Invalid habit timestamp';
    end if;
    begin perform stamp::timestamptz;
    exception when others then raise exception using errcode='22023', message='Invalid habit timestamp'; end;
  end loop;
  if p_type='habit' then
    if (not p_partial or p_data ? 'title') and (pg_catalog.jsonb_typeof(p_data->'title') is distinct from 'string' or pg_catalog.btrim(p_data->>'title')=''
      or pg_catalog.char_length(p_data->>'title')>200) then
      raise exception using errcode='22023', message='Invalid habit title';
    end if;
    if p_data->'reminderMinutes' is not null and p_data->'reminderMinutes' <> 'null'::jsonb and
      (pg_catalog.jsonb_typeof(p_data->'reminderMinutes') <> 'number' or (p_data->>'reminderMinutes') !~ '^[0-9]+$'
        or (p_data->>'reminderMinutes')::numeric > 1439) then
      raise exception using errcode='22023', message='Invalid habit reminder';
    end if;
    if not p_partial or p_data ? 'scheduleHistory' then
    if pg_catalog.jsonb_typeof(p_data->'scheduleHistory') is distinct from 'array' or pg_catalog.jsonb_array_length(p_data->'scheduleHistory')=0 then
      raise exception using errcode='22023', message='Invalid habit schedule';
    end if;
    for version in select value from pg_catalog.jsonb_array_elements(p_data->'scheduleHistory') loop
      if pg_catalog.jsonb_typeof(version) is distinct from 'object' or exists(select 1 from pg_catalog.jsonb_object_keys(version) k where k not in ('effectiveFrom','startDate','endDate','weekdays','targetPerDay','dayPeriod','periodTargets')) then
        raise exception using errcode='22023', message='Invalid habit schedule';
      end if;
      effective:=private.pomodoist_habit_date(version->'effectiveFrom');
      start_day:=private.pomodoist_habit_date(version->'startDate');end_day:=null;
      if version->'endDate' is not null and version->'endDate' <> 'null'::jsonb then end_day:=private.pomodoist_habit_date(version->'endDate'); end if;
      if (last_effective is not null and effective<=last_effective) or (end_day is not null and end_day<start_day)
        or pg_catalog.jsonb_typeof(version->'targetPerDay') is distinct from 'number'
        or coalesce(version->>'targetPerDay','') !~ '^[0-9]+$' then
        raise exception using errcode='22023', message='Invalid habit schedule';
      end if;
      if (version->>'targetPerDay')::numeric not between 1 and 99 then
        raise exception using errcode='22023', message='Invalid habit schedule';
      end if;
      if version ? 'dayPeriod' and (
        pg_catalog.jsonb_typeof(version->'dayPeriod') is distinct from 'string'
        or version->>'dayPeriod' not in ('automatic','anytime','morning','afternoon','evening','night')) then
        raise exception using errcode='22023', message='Invalid habit day period';
      end if;
      if version ? 'periodTargets' then
        if pg_catalog.jsonb_typeof(version->'periodTargets') is distinct from 'object'
          or version->'periodTargets' = '{}'::jsonb
          or (version ? 'dayPeriod' and version->>'dayPeriod' <> 'automatic') then
          raise exception using errcode='22023', message='Invalid habit period targets';
        end if;
        quota_total := 0;
        for quota in select * from pg_catalog.jsonb_each(version->'periodTargets') loop
          if quota.key not in ('morning','afternoon','evening','night')
            or pg_catalog.jsonb_typeof(quota.value) is distinct from 'number'
            or (quota.value #>> '{}') !~ '^[0-9]+$' then
            raise exception using errcode='22023', message='Invalid habit period targets';
          end if;
          if (quota.value #>> '{}')::numeric not between 1 and 99 then
            raise exception using errcode='22023', message='Invalid habit period targets';
          end if;
          quota_total := quota_total + (quota.value #>> '{}')::numeric;
        end loop;
        if quota_total <> (version->>'targetPerDay')::numeric then
          raise exception using errcode='22023', message='Invalid habit period targets';
        end if;
      end if;
      last_effective:=effective;weekdays:=version->'weekdays';
      if pg_catalog.jsonb_typeof(weekdays) is distinct from 'array' then raise exception using errcode='22023', message='Invalid habit weekdays'; end if;
      if pg_catalog.jsonb_array_length(weekdays) not between 1 and 7
        or exists(select 1 from pg_catalog.jsonb_array_elements(weekdays) d where pg_catalog.jsonb_typeof(d)<>'number' or d::text !~ '^[1-7]$')
        or (select count(distinct d) from pg_catalog.jsonb_array_elements(weekdays) d) <> pg_catalog.jsonb_array_length(weekdays) then
        raise exception using errcode='22023', message='Invalid habit weekdays';
      end if;
    end loop;
    end if;
    if p_data->'projectId' is not null and p_data->'projectId' <> 'null'::jsonb and
      (pg_catalog.jsonb_typeof(p_data->'projectId')<>'string' or p_data->>'projectId'='') then
      raise exception using errcode='22023', message='Habit project must belong to the same account and be personal';
    end if;
  else
    if p_data ? 'dayPeriod' and (
      pg_catalog.jsonb_typeof(p_data->'dayPeriod') is distinct from 'string'
      or p_data->>'dayPeriod' not in ('anytime','morning','afternoon','evening','night')) then
      raise exception using errcode='22023', message='Invalid check-in day period';
    end if;
    if not p_partial or p_data ? 'day' then perform private.pomodoist_habit_date(p_data->'day'); end if;
    if (not p_partial or p_data ? 'habitId') and pg_catalog.jsonb_typeof(p_data->'habitId') is distinct from 'string' then
      raise exception using errcode='22023', message='Invalid check-in habit';
    end if;
  end if;
end;
$$;


-- Extend existing MCP gateways without duplicating their mutation/auth logic.
do $$
declare definition text; needle text;
begin
  definition := pg_catalog.pg_get_functiondef('public.push_pomodoist_mcp_changes(uuid,uuid,jsonb)'::regprocedure);
  if pg_catalog.strpos(definition, '''habit_check_in''') = 0 then
    needle := E'        ''kanban_settings''\n      )';
    if pg_catalog.strpos(definition, needle) = 0 then
      raise exception 'Unexpected MCP entity allowlist';
    end if;
    execute pg_catalog.replace(definition, needle, E'        ''kanban_settings'',\n        ''habit'',\n        ''habit_check_in''\n      )');
  end if;
  definition := pg_catalog.pg_get_functiondef('public.pomodoist_openclaw_action(uuid,uuid,uuid,uuid,text,text,bigint,jsonb,jsonb)'::regprocedure);
  if pg_catalog.strpos(definition, '''create_habit''') = 0 then
    needle := '''set_task_details'',''focus'')';
    if pg_catalog.strpos(definition, needle) = 0 then
      raise exception 'Unexpected guarded MCP action allowlist';
    end if;
    execute pg_catalog.replace(definition, needle,
      '''set_task_details'',''focus'',''create_habit'',''update_habit'',''add_habit_check_in'',''complete_habit'',''undo_habit_check_in'',''finish_habit'',''reopen_habit'',''delete_habit'')');
  end if;
end;
$$;

create or replace function public.read_pomodoist_mcp(p_user_id uuid, p_operation text, p_arguments jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  if p_operation in ('habit_snapshot', 'mutation_snapshot') then
    if p_user_id is null or p_arguments is distinct from '{}'::jsonb then
      raise exception using errcode='22023', message='Invalid Pomodoist MCP read request';
    end if;
    if p_operation = 'mutation_snapshot' then
      return private.pomodoist_mcp_mutation_snapshot(p_user_id);
    end if;
    return pg_catalog.jsonb_build_object(
      'serverNow', pg_catalog.clock_timestamp(),
      'habits', coalesce((select pg_catalog.jsonb_agg(data || pg_catalog.jsonb_build_object('id',entity_id) order by entity_id)
        from public.sync_entities where user_id=p_user_id and app_id='pomodoist' and entity_type='habit'
          and deleted_at is null and pg_catalog.jsonb_typeof(data)='object' and data->>'isDeleted' is distinct from 'true'), '[]'::jsonb),
      'checkIns', coalesce((select pg_catalog.jsonb_agg(c.data || pg_catalog.jsonb_build_object('id',c.entity_id) order by c.entity_id)
        from public.sync_entities c where c.user_id=p_user_id and c.app_id='pomodoist' and c.entity_type='habit_check_in'
          and c.deleted_at is null and pg_catalog.jsonb_typeof(c.data)='object' and c.data->>'isDeleted' is distinct from 'true'
          and exists(select 1 from public.sync_entities h where h.user_id=p_user_id and h.app_id='pomodoist' and h.entity_type='habit'
            and h.entity_id=c.data->>'habitId' and h.deleted_at is null and pg_catalog.jsonb_typeof(h.data)='object' and h.data->>'isDeleted' is distinct from 'true')), '[]'::jsonb),
      'projects', coalesce((select pg_catalog.jsonb_agg(data || pg_catalog.jsonb_build_object('id',entity_id) order by entity_id)
        from public.sync_entities where user_id=p_user_id and app_id='pomodoist' and entity_type='project'
          and deleted_at is null and pg_catalog.jsonb_typeof(data)='object' and data->>'scopeId' is null
          and data->>'isArchived' is distinct from 'true' and data->>'isDeleted' is distinct from 'true'), '[]'::jsonb)
    );
  end if;
  return private.read_pomodoist_mcp_v1(p_user_id,p_operation,p_arguments);
end;
$$;
revoke all on function public.read_pomodoist_mcp(uuid,text,jsonb) from public;
grant execute on function public.read_pomodoist_mcp(uuid,text,jsonb) to service_role;
