create or replace function private.on_pomodoist_task_calendar_change()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_user_id uuid;
  v_task_id text;
  v_updated_at timestamptz;
begin
  if tg_op = 'DELETE' then
    if old.app_id <> 'pomodoist' or old.entity_type <> 'task' then return old; end if;
    v_user_id := old.user_id;
    v_task_id := old.entity_id;
    v_updated_at := old.client_updated_at;
    if not exists (select 1 from public.profiles where id = v_user_id) then return old; end if;
  else
    if new.app_id = 'pomodoist'
      and new.entity_type = 'google_calendar_connection'
      and new.entity_id = 'primary'
      and coalesce(new.data ->> 'ownerDeviceId', '') <> 'google-calendar-server'
      and exists (
        select 1
        from private.pomodoist_google_calendar_accounts account
        where account.user_id = new.user_id and account.status <> 'disconnected'
    )
    then
      update private.pomodoist_google_calendar_accounts account
      set updated_at = greatest(
        account.updated_at,
        new.client_updated_at + interval '1 microsecond',
        pg_catalog.now()
      )
      where account.user_id = new.user_id;
      perform private.project_pomodoist_google_calendar_connection(new.user_id);
      return new;
    end if;
    if new.app_id <> 'pomodoist' or new.entity_type <> 'task' then return new; end if;
    v_user_id := new.user_id;
    v_task_id := new.entity_id;
    v_updated_at := new.client_updated_at;
  end if;
  if tg_op = 'INSERT'
    or tg_op = 'DELETE'
    or old.data -> 'dueJson' is distinct from new.data -> 'dueJson'
    or old.deleted_at is distinct from new.deleted_at
  then
    insert into private.pomodoist_google_calendar_task_state (
      user_id, task_id, local_schedule_updated_at
    ) values (v_user_id, v_task_id, v_updated_at)
    on conflict (user_id, task_id) do update
    set local_schedule_updated_at = excluded.local_schedule_updated_at;
  end if;
  perform private.queue_pomodoist_google_calendar(v_user_id);
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;
