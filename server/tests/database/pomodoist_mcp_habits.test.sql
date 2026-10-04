begin;
select plan(1);
insert into auth.users(id,email,aud,role,created_at,updated_at) values
 ('ab910000-0000-4000-8000-000000000001','mcp-habits-a@example.test','authenticated','authenticated',now(),now()),
 ('ab910000-0000-4000-8000-000000000002','mcp-habits-b@example.test','authenticated','authenticated',now(),now());

-- Keep assertions executable in an isolated PostgreSQL as well as pgTAP.
do $$
declare
  account_a uuid := 'ab910000-0000-4000-8000-000000000001';
  account_b uuid := 'ab910000-0000-4000-8000-000000000002';
  client uuid := 'ab910000-0000-4000-8000-000000000003';
  habit_id text := 'ab910000-0000-4000-8000-000000000010';
  mark_id text := 'ab910000-0000-4000-8000-000000000011';
  payload jsonb := jsonb_build_object('id',habit_id,'userId','local-user','title','Water','projectId',null,'reminderMinutes',null,
    'scheduleHistory',jsonb_build_array(jsonb_build_object('effectiveFrom','2026-10-03','startDate','2026-10-03','endDate',null,
      'weekdays',jsonb_build_array(1,2,3,4,5,6,7),'targetPerDay',7,'periodTargets',jsonb_build_object('morning',2,'afternoon',2,'evening',2,'night',1))),
    'createdAt','2026-10-03T12:00:00Z','updatedAt','2026-10-03T12:00:00Z','isDeleted',false);
  mark_data jsonb;
  op jsonb;
  snapshot jsonb;
  operation text;
  bad_args jsonb;
  action text;
begin
  op := jsonb_build_object('opId','mcp-habit-create','entityType','habit','entityId',habit_id,'operation','upsert','payload',payload,'clientUpdatedAt','2026-10-03T12:00:00Z');
  perform public.push_pomodoist_mcp_changes(account_a,client,jsonb_build_array(op));
  perform public.push_pomodoist_mcp_changes(account_b,client,jsonb_build_array(op || jsonb_build_object('opId','foreign-habit-create','payload',payload || '{"title":"Foreign water"}'::jsonb)));
  mark_data := jsonb_build_object('id',mark_id,'userId','local-user','habitId',habit_id,'day','2026-10-03','dayPeriod','night',
    'createdAt','2026-10-03T13:00:00Z','updatedAt','2026-10-03T13:00:00Z','isDeleted',false);
  op := op || jsonb_build_object('opId','mcp-habit-night','entityType','habit_check_in','entityId',mark_id,'payload',mark_data);
  perform public.push_pomodoist_mcp_changes(account_a,client,jsonb_build_array(op));
  snapshot := public.read_pomodoist_mcp(account_a,'habit_snapshot','{}');
  if jsonb_array_length(snapshot->'habits') <> 1 or snapshot #>> '{habits,0,title}' <> 'Water'
    or snapshot #>> '{habits,0,scheduleHistory,0,periodTargets,night}' <> '1'
    or jsonb_array_length(snapshot->'checkIns') <> 1 or snapshot #>> '{checkIns,0,dayPeriod}' <> 'night'
    or snapshot->>'serverNow' is null then raise exception 'MCP habit snapshot lost account data'; end if;
  if jsonb_array_length(public.read_pomodoist_mcp(account_b,'habit_snapshot','{}')->'checkIns') <> 0 then
    raise exception 'MCP snapshot leaked check-ins across accounts'; end if;
  if has_function_privilege('authenticated','public.read_pomodoist_mcp(uuid,text,jsonb)','execute')
    or not has_function_privilege('service_role','public.read_pomodoist_mcp(uuid,text,jsonb)','execute') then
    raise exception 'MCP snapshot privileges changed'; end if;
  -- The inbox is personal; shared, archived and deleted project rows must be omitted.
  insert into public.sync_entities(user_id,app_id,entity_type,entity_id,server_revision,client_updated_at,data) values
    (account_a,'pomodoist','project','mcp-shared',1,now(),'{"id":"mcp-shared","scopeId":"scope"}'),
    (account_a,'pomodoist','project','mcp-archived',1,now(),'{"id":"mcp-archived","isArchived":true}'),
    (account_a,'pomodoist','project','mcp-deleted',1,now(),'{"id":"mcp-deleted","isDeleted":true}'),
    (account_b,'pomodoist','project','mcp-foreign',1,now(),'{"id":"mcp-foreign"}');
  snapshot := public.read_pomodoist_mcp(account_a,'habit_snapshot','{}');
  if exists(select 1 from jsonb_array_elements(snapshot->'projects') p where p->>'id' like 'mcp-%') then
    raise exception 'MCP snapshot exposed an ineligible project'; end if;
  foreach operation in array array['habit_snapshot','mutation_snapshot'] loop
    foreach bad_args in array array[null::jsonb,'null'::jsonb,'[]'::jsonb,'{"user_id":"spoofed"}'::jsonb] loop
      begin
        perform public.read_pomodoist_mcp(account_a,operation,bad_args);
        raise exception 'Expected nonempty or null snapshot arguments to fail';
      exception when sqlstate '22023' then null; end;
    end loop;
  end loop;
  begin
    perform public.read_pomodoist_mcp(null,'habit_snapshot','{}');
    raise exception 'Expected a missing account to fail';
  exception when sqlstate '22023' then null; end;
  begin
    perform public.push_pomodoist_mcp_changes(account_a,client,jsonb_build_array(op || jsonb_build_object('opId','spoofed-habit','payload',mark_data || jsonb_build_object('userId',account_b))));
    raise exception 'Expected caller-supplied account identity to fail';
  exception when sqlstate '22023' then null; end;
  perform public.push_pomodoist_mcp_changes(account_a,client,jsonb_build_array(op || '{"opId":"mcp-habit-undo","operation":"delete","payload":{},"clientUpdatedAt":"2026-10-03T14:00:00Z"}'::jsonb));
  if jsonb_array_length(public.read_pomodoist_mcp(account_a,'habit_snapshot','{}')->'checkIns') <> 0 then
    raise exception 'Undone mark remains in snapshot'; end if;
  perform public.push_pomodoist_mcp_changes(account_a,client,jsonb_build_array(op || jsonb_build_object('opId','mcp-habit-delete','entityType','habit','entityId',habit_id,'operation','delete','payload','{}'::jsonb,'clientUpdatedAt','2026-10-03T15:00:00Z')));
  if jsonb_array_length(public.read_pomodoist_mcp(account_a,'habit_snapshot','{}')->'habits') <> 0
    or jsonb_array_length(public.read_pomodoist_mcp(account_b,'habit_snapshot','{}')->'habits') <> 1 then
    raise exception 'Deleted habit remains visible or another account was affected'; end if;
  foreach action in array array['create_habit','update_habit','add_habit_check_in','complete_habit','undo_habit_check_in','finish_habit','reopen_habit','delete_habit'] loop
    if strpos(pg_get_functiondef('public.pomodoist_openclaw_action(uuid,uuid,uuid,uuid,text,text,bigint,jsonb,jsonb)'::regprocedure),quote_literal(action)) = 0 then
      raise exception 'Missing guarded action %',action; end if;
  end loop;
  if strpos(pg_get_functiondef('public.pomodoist_openclaw_action(uuid,uuid,uuid,uuid,text,text,bigint,jsonb,jsonb)'::regprocedure),'pomodoist-file-lifecycle') = 0 then
    raise exception 'Habit allowlist replacement lost the existing lifecycle lock'; end if;
end;
$$;
select pass('MCP habits share sync validation, account ownership, tombstones and guarded action allowlists');
select * from finish();
rollback;
