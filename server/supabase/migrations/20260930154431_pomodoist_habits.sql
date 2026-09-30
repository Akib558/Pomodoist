-- Deploy before releasing clients with Drift schema version 9.
-- Personal habits use the existing account sync protocol and tombstone rules.
create function private.pomodoist_habit_date(p_value jsonb) returns date
language plpgsql immutable set search_path = '' as $$
declare d date;
begin
  if pg_catalog.jsonb_typeof(p_value) is distinct from 'string'
    or (p_value #>> '{}') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then
    raise exception using errcode='22023', message='Invalid habit date';
  end if;
  begin d := (p_value #>> '{}')::date;
  exception when others then raise exception using errcode='22023', message='Invalid habit date'; end;
  if pg_catalog.to_char(d,'YYYY-MM-DD') <> p_value #>> '{}' or d < date '0001-01-01' then
    raise exception using errcode='22023', message='Invalid habit date';
  end if;
  return d;
end;
$$;

create function private.validate_pomodoist_habit_payload(p_type text,p_id text,p_user_id uuid,p_data jsonb,p_partial boolean) returns void
language plpgsql set search_path = '' as $$
declare version jsonb; key text; weekdays jsonb; effective date; last_effective date; start_day date; end_day date; stamp text;
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
      else array['id','userId','habitId','day','createdAt','updatedAt','isDeleted'] end)) then
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
      if pg_catalog.jsonb_typeof(version) is distinct from 'object' or exists(select 1 from pg_catalog.jsonb_object_keys(version) k where k not in ('effectiveFrom','startDate','endDate','weekdays','targetPerDay')) then
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
    if not p_partial or p_data ? 'day' then perform private.pomodoist_habit_date(p_data->'day'); end if;
    if (not p_partial or p_data ? 'habitId') and pg_catalog.jsonb_typeof(p_data->'habitId') is distinct from 'string' then
      raise exception using errcode='22023', message='Invalid check-in habit';
    end if;
  end if;
end;
$$;

create function private.validate_pomodoist_habit_entity() returns trigger
language plpgsql security definer set search_path = '' as $$
declare habit_data jsonb := new.data; previous jsonb; parent_deleted timestamptz; project text; parent_found boolean;
begin
  if new.app_id <> 'pomodoist' or new.entity_type not in ('habit','habit_check_in') then return new; end if;
  -- A deletion may arrive before its creation. Keep an empty tombstone valid.
  if new.deleted_at is not null then return new; end if;
  perform private.validate_pomodoist_habit_payload(new.entity_type,new.entity_id,new.user_id,habit_data,false);
  select e.data into previous from public.sync_entities e where e.user_id=new.user_id and e.app_id=new.app_id
    and e.entity_type=new.entity_type and e.entity_id=new.entity_id;
  if new.entity_type='habit' then
    if habit_data->'projectId' is not null and habit_data->'projectId' <> 'null'::jsonb then
      project:=habit_data->>'projectId';
      if pg_catalog.jsonb_typeof(habit_data->'projectId') <> 'string' or project='' or not exists(
        select 1 from public.sync_entities e where e.user_id=new.user_id and e.app_id=new.app_id
          and e.entity_type='project' and e.entity_id=project and (e.data->>'scopeId' is null or previous->>'projectId'=project)) then
        raise exception using errcode='22023', message='Habit project must belong to the same account and be personal';
      end if;
    end if;
  else
    select e.deleted_at,true into parent_deleted,parent_found from public.sync_entities e where e.user_id=new.user_id
      and e.app_id=new.app_id and e.entity_type='habit' and e.entity_id=habit_data->>'habitId';
    if not coalesce(parent_found,false) then raise exception using errcode='22023', message='Check-in habit must belong to the same account'; end if;
    if previous is not null and (previous->>'habitId' is distinct from habit_data->>'habitId' or previous->>'day' is distinct from habit_data->>'day'
      or previous->>'createdAt' is distinct from habit_data->>'createdAt') then
      raise exception using errcode='22023', message='Check-in identity is immutable';
    end if;
    -- Late offline deliveries must never recreate a deleted habit or its progress.
    if parent_deleted is not null then new.deleted_at:=parent_deleted; end if;
  end if;
  return new;
end;
$$;
revoke all on function private.pomodoist_habit_date(jsonb) from public;
revoke all on function private.validate_pomodoist_habit_entity() from public;
create trigger pomodoist_habit_validation before insert or update on public.sync_entities
  for each row execute function private.validate_pomodoist_habit_entity();

revoke all on function private.validate_pomodoist_habit_payload(text,text,uuid,jsonb,boolean) from public;

CREATE OR REPLACE FUNCTION private.push_changes_for_user(p_user_id uuid, p_app_id text, p_device_id text, p_operations jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare
  v_op jsonb; v_op_id text; v_entity_type text; v_entity_id text;
  v_operation text; v_payload jsonb; v_client_updated_at timestamptz;
  v_revision bigint; v_inserted boolean; v_existing public.sync_entities%rowtype;
  v_data jsonb; v_clock jsonb; v_field_key text; v_field_value jsonb;
  v_field_clock timestamptz; v_deleted_at timestamptz;
  v_is_protected_pomodoist_anchor boolean;
  v_applied jsonb := '[]'::jsonb; v_server_revision bigint := 0;
begin
  if p_user_id is null then raise exception 'Authentication required'; end if;

  -- Validate the entire batch before locks, device updates or operation receipts.
  -- SQL NULL remains an empty batch for existing internal callers.
  if p_operations is not null and pg_catalog.jsonb_typeof(p_operations) <> 'array' then
    raise exception using errcode = '22023', message = 'Invalid sync batch: expected an array';
  end if;
  for v_op in select value from pg_catalog.jsonb_array_elements(coalesce(p_operations, '[]'::jsonb)) loop
    if pg_catalog.jsonb_typeof(v_op) <> 'object' then
      raise exception using errcode = '22023', message = 'Invalid sync operation: expected an object';
    end if;
    for v_field_key, v_field_value in
      select * from (values
        ('opId', coalesce(nullif(v_op -> 'opId', 'null'::jsonb), v_op -> 'op_id')),
        ('entityType', coalesce(nullif(v_op -> 'entityType', 'null'::jsonb), v_op -> 'entity_type')),
        ('entityId', coalesce(nullif(v_op -> 'entityId', 'null'::jsonb), v_op -> 'entity_id'))
      ) as identifiers(name, value)
    loop
      if pg_catalog.jsonb_typeof(v_field_value) is distinct from 'string'
         or pg_catalog.btrim(v_field_value #>> '{}') = '' then
        raise exception using errcode = '22023',
          message = 'Invalid sync identifier: ' || v_field_key;
      end if;
    end loop;
    if coalesce(v_op ->> 'operation', 'upsert') not in ('upsert', 'delete') then
      raise exception using errcode = '22023', message = 'Invalid sync operation: expected upsert or delete';
    end if;
    if coalesce(pg_catalog.jsonb_typeof(v_op -> 'payload'), 'object') <> 'object' then
      raise exception using errcode = '22023', message = 'Invalid sync payload: expected an object';
    end if;
    if p_app_id = 'pomodoist' and coalesce(v_op ->> 'operation','upsert') = 'upsert' then
      perform private.validate_pomodoist_habit_payload(
        coalesce(v_op->>'entityType',v_op->>'entity_type'),
        coalesce(v_op->>'entityId',v_op->>'entity_id'),p_user_id,
        coalesce(v_op->'payload','{}'::jsonb),true);
    end if;
  end loop;
  if p_app_id = 'pomodoist' then
    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended('pomodoist-google-calendar:' || p_user_id::text, 0));
  end if;
  insert into public.sync_devices (user_id, app_id, device_id, last_seen_at)
  values (p_user_id, p_app_id, p_device_id, pg_catalog.timezone('utc', pg_catalog.now()))
  on conflict (user_id, app_id, device_id) do update
  set last_seen_at = excluded.last_seen_at
  where public.sync_devices.last_seen_at < excluded.last_seen_at - interval '5 minutes';

  for v_op in select value from pg_catalog.jsonb_array_elements(coalesce(p_operations, '[]'::jsonb)) loop
    v_op_id := coalesce(v_op ->> 'opId', v_op ->> 'op_id');
    v_entity_type := coalesce(v_op ->> 'entityType', v_op ->> 'entity_type');
    v_entity_id := coalesce(v_op ->> 'entityId', v_op ->> 'entity_id');
    v_operation := coalesce(v_op ->> 'operation', 'upsert');
    v_payload := coalesce(v_op -> 'payload', '{}'::jsonb);
    v_client_updated_at := coalesce(nullif(coalesce(v_op ->> 'clientUpdatedAt', v_op ->> 'client_updated_at'), '')::timestamptz,
      pg_catalog.timezone('utc', pg_catalog.now()));
    if v_op_id is null or v_entity_type is null or v_entity_id is null then
      raise exception 'Invalid sync operation: %', v_op;
    end if;
    v_is_protected_pomodoist_anchor := p_app_id = 'pomodoist' and (
      (v_entity_type = 'project' and v_entity_id = 'inbox') or
      (v_entity_type = 'label' and v_entity_id in ('kanban-status-backlog-v1', 'kanban-status-done-v1')) or
      (v_entity_type = 'kanban_settings' and v_entity_id = 'kanban-settings-primary-v1'));
    if v_operation = 'delete' and v_is_protected_pomodoist_anchor then
      raise exception using errcode = '22023', message = pg_catalog.format(
        'Protected Pomodoist system anchor cannot be deleted: %s/%s', v_entity_type, v_entity_id);
    end if;
    v_revision := pg_catalog.nextval('public.sync_revision_seq');
    v_inserted := false;
    insert into public.sync_operation_receipts (user_id, op_id, server_revision)
    values (p_user_id, v_op_id, v_revision) on conflict (user_id, op_id) do nothing
    returning true into v_inserted;
    if not coalesce(v_inserted, false) then continue; end if;
    select * into v_existing from public.sync_entities
    where user_id = p_user_id and app_id = p_app_id and entity_type = v_entity_type and entity_id = v_entity_id
    for update;
    v_data := coalesce(v_existing.data, '{}'::jsonb);
    v_clock := coalesce(v_existing.field_clock, '{}'::jsonb);
    v_deleted_at := v_existing.deleted_at;
    if v_operation = 'delete' then
      v_deleted_at := coalesce(v_deleted_at, v_client_updated_at);
    elsif v_deleted_at is null or v_is_protected_pomodoist_anchor then
      v_deleted_at := null;
      for v_field_key, v_field_value in select key, value from pg_catalog.jsonb_each(v_payload) loop
        v_field_clock := nullif(v_clock ->> v_field_key, '')::timestamptz;
        if v_field_clock is null or v_field_clock <= v_client_updated_at then
          v_data := pg_catalog.jsonb_set(v_data, array[v_field_key], v_field_value, true);
          v_clock := pg_catalog.jsonb_set(v_clock, array[v_field_key], pg_catalog.to_jsonb(v_client_updated_at), true);
        end if;
      end loop;
    end if;
    insert into public.sync_entities (user_id, app_id, entity_type, entity_id, server_revision,
      client_updated_at, deleted_at, data, field_clock)
    values (p_user_id, p_app_id, v_entity_type, v_entity_id, v_revision, v_client_updated_at, v_deleted_at, v_data, v_clock)
    on conflict (user_id, app_id, entity_type, entity_id) do update
    set server_revision = excluded.server_revision, client_updated_at = excluded.client_updated_at,
      deleted_at = excluded.deleted_at, data = excluded.data, field_clock = excluded.field_clock;
    v_server_revision := greatest(v_server_revision, v_revision);
    v_applied := v_applied || pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object(
      'entityType', v_entity_type, 'entityId', v_entity_id, 'serverRevision', v_revision,
      'deletedAt', v_deleted_at, 'data', v_data, 'updatedAt', v_client_updated_at));
  end loop;
  select coalesce(pg_catalog.max(server_revision), 0) into v_server_revision
  from public.sync_entities where user_id = p_user_id and app_id = p_app_id;
  return pg_catalog.jsonb_build_object('serverRevision', v_server_revision, 'applied', v_applied);
end;
$$;


