-- pg_net dispatch success is not evidence of worker success. Keep the latest
-- request ID so a separate Cron transaction can inspect its completed response.
create table private.pomodoist_files_cleanup_request (
  singleton boolean primary key default true check (singleton),
  request_id bigint not null,
  requested_at timestamptz not null default now(),
  checked boolean not null default false
);
revoke all on private.pomodoist_files_cleanup_request from public, anon, authenticated, service_role;

create or replace function private.invoke_pomodoist_files_cleanup() returns bigint
language plpgsql security definer set search_path='' as $$
declare address text; secret text; request_id bigint;
begin
  if not exists(select 1 from private.pomodoist_storage_deletions)
    and not exists(select 1 from private.pomodoist_uploads where finished_at is null and deleted_at is null and expires_at<=now()) then return null; end if;
  select decrypted_secret into address from vault.decrypted_secrets where name='pomodoist-files-cleanup-url' order by updated_at desc limit 1;
  select decrypted_secret into secret from vault.decrypted_secrets where name='pomodoist-files-cleanup-secret' order by updated_at desc limit 1;
  if coalesce(address,'')='' or coalesce(secret,'')='' then
    raise exception 'File cleanup worker is not configured';
  end if;
  select net.http_post(url:=address,body:='{}'::jsonb,
    headers:=jsonb_build_object('Content-Type','application/json','X-Pomodoist-Cleanup-Secret',secret),
    timeout_milliseconds:=55000) into request_id;
  insert into private.pomodoist_files_cleanup_request as current_request(singleton,request_id,requested_at,checked)
  values(true,request_id,now(),false)
  on conflict(singleton) do update set request_id=excluded.request_id, requested_at=excluded.requested_at, checked=false;
  return request_id;
end $$;
revoke all on function private.invoke_pomodoist_files_cleanup() from public,anon,authenticated,service_role;

create function private.check_pomodoist_files_cleanup() returns void
language plpgsql security definer set search_path='' as $$
declare dispatched private.pomodoist_files_cleanup_request%rowtype; response net._http_response%rowtype;
begin
  select * into dispatched from private.pomodoist_files_cleanup_request where singleton and not checked;
  if not found then return; end if;
  select * into response from net._http_response where id=dispatched.request_id;
  if not found then
    if dispatched.requested_at <= now()-interval '2 minutes' then
      raise exception 'File cleanup request % has no HTTP response', dispatched.request_id;
    end if;
    return;
  end if;
  if response.status_code is distinct from 200 or coalesce(response.timed_out,false) or response.error_msg is not null then
    raise exception 'File cleanup request % failed (HTTP %, timeout %)', dispatched.request_id, response.status_code, coalesce(response.timed_out,false);
  end if;
  if response.content::jsonb->'ok' is distinct from 'true'::jsonb then
    raise exception 'File cleanup request % did not confirm completion', dispatched.request_id;
  end if;
  update private.pomodoist_files_cleanup_request set checked=true where request_id=dispatched.request_id;
end $$;
revoke all on function private.check_pomodoist_files_cleanup() from public,anon,authenticated,service_role;

select cron.schedule('pomodoist-files-cleanup-response','* * * * *','select private.check_pomodoist_files_cleanup();');
