-- Keep the loop variable distinct from the uploads table alias.
-- CREATE OR REPLACE preserves the existing service-only execution grants.
CREATE OR REPLACE FUNCTION private.pomodoist_collaboration_storage_cleanup(p_deleted text[] default array[]::text[]) returns jsonb
language plpgsql security definer set search_path='' as $$
declare expired_upload_id uuid;
begin
  if coalesce(current_setting('request.jwt.claims',true),'{}')::jsonb->>'role' is distinct from 'service_role' then
    raise exception using errcode='42501',message='Service role required'; end if;
  perform pg_advisory_xact_lock(hashtextextended('pomodoist-file-lifecycle',0));
  for expired_upload_id in select id from private.pomodoist_uploads
    where finished_at is null and expires_at<=now() and deleted_at is null loop
    perform private.pomodoist_file_delete(expired_upload_id);
  end loop;
  -- Migrate existing queue records and retain capability retry protection even
  -- when a signed upload arrives after the first successful Storage deletion.
  insert into private.pomodoist_storage_deletions(object_path,retain_until)
    select object_path,greatest(now(),expires_at + interval '2 hours' + interval '5 minutes') from private.pomodoist_uploads
      where deleted_at is not null and storage_deleted_at is null
    on conflict(object_path) do update set retain_until=greatest(pomodoist_storage_deletions.retain_until,excluded.retain_until);
  update private.pomodoist_uploads u set storage_deleted_at=now()
    from private.pomodoist_storage_deletions d where u.object_path=d.object_path
      and d.object_path=any(p_deleted) and d.retain_until<=now();
  delete from private.pomodoist_storage_deletions where object_path=any(p_deleted) and retain_until<=now();
  -- Move retained acknowledgements behind other entries instead of starving
  -- large deletion queues while waiting for the capability window to close.
  update private.pomodoist_storage_deletions set created_at=now() where object_path=any(p_deleted);
  return jsonb_build_object('paths',coalesce((select jsonb_agg(object_path) from
    (select object_path from private.pomodoist_storage_deletions order by created_at,object_path limit 100) q),'[]'::jsonb));
end $$;
