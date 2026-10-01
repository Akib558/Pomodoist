-- A signed, unexpired JWT can outlive a revoked Auth session.
create function private.pomodoist_session_is_active()
returns boolean
language plpgsql stable security definer
set search_path = ''
as $$
declare
  session_id uuid;
begin
  begin
    session_id := (auth.jwt()->>'session_id')::uuid;
  exception when invalid_text_representation then
    return false;
  end;
  return exists (
    select 1 from auth.sessions s
    where s.id = session_id and s.user_id = auth.uid()
      and s.oauth_client_id is null
      and (s.not_after is null or s.not_after > statement_timestamp())
  );
end;
$$;

revoke all on function private.pomodoist_session_is_active() from public, anon, authenticated, service_role;
grant execute on function private.pomodoist_session_is_active() to authenticated;

-- This also protects SECURITY DEFINER RPCs, which bypass table RLS.
create function public.pomodoist_check_session()
returns void
language plpgsql
set search_path = ''
as $$
begin
  if auth.jwt()->>'role' = 'authenticated' then
    if not private.pomodoist_session_is_active() then
      raise sqlstate 'PT401' using message = 'Session is no longer active';
    end if;
  end if;
end;
$$;

revoke all on function public.pomodoist_check_session() from public;
grant execute on function public.pomodoist_check_session() to anon, authenticated, service_role, pomodoist_mcp;
alter role authenticator set pgrst.db_pre_request = 'public.pomodoist_check_session';

-- Restrictive policies supplement ownership checks on direct table access,
-- including Realtime authorization, where the Data API hook does not run.
do $$
declare
  target text;
begin
  foreach target in array array[
    'public.apps', 'public.products', 'public.quota_definitions',
    'public.profiles', 'public.user_app_installs', 'public.user_entitlements',
    'public.usage_periods', 'public.storage_usage', 'public.sync_devices',
    'public.sync_entities', 'public.sync_operations', 'realtime.messages'
  ] loop
    execute format(
      'create policy "Require active account session" on %s as restrictive
       for all to authenticated
       using ((select private.pomodoist_session_is_active()))
       with check ((select private.pomodoist_session_is_active()))', target
    );
  end loop;
end;
$$;

notify pgrst, 'reload config';
notify pgrst, 'reload schema';
