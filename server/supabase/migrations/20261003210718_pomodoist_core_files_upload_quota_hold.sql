-- Signed upload URLs authorize the bucket maximum, not the declared file size.
-- Hold that maximum until finalization or confirmed deletion after URL expiry.
do $quota_hold$
declare definition text; original text; replacement text;
begin
  definition := pg_get_functiondef('private.pomodoist_files(jsonb)'::regprocedure);
  original := $old$select coalesce(sum(bytes),0) into held from private.pomodoist_uploads where quota_user_id=payer
    and finished_at is null and deleted_at is null and expires_at>now() and (u.id is null or id<>u.id);$old$;
  replacement := $new$select count(*)*20000000 into held from private.pomodoist_uploads where quota_user_id=payer
    and storage_deleted_at is null and (finished_at is null or deleted_at is not null)
    and (u.id is null or id<>u.id);$new$;
  if strpos(definition,original)=0 then raise exception 'Unexpected pending file quota definition'; end if;
  definition := replace(definition,original,replacement);

  original := 'used_month+held+amount>1000000000 or used_year+held+amount>5000000000';
  if strpos(definition,original)=0 then raise exception 'Unexpected upload reservation quota definition'; end if;
  definition := replace(definition,original,'used_month+held+20000000>1000000000 or used_year+held+20000000>5000000000');

  original := $old$where id=''pomodoist-shared'' and not public)$old$;
  if strpos(definition,original)=0 then raise exception 'Unexpected file bucket guard'; end if;
  definition := replace(definition,original,$new$where id=''pomodoist-shared'' and not public and file_size_limit between 1 and 20000000)$new$);

  original := $old$if action='capabilities' then
    return jsonb_build_object$old$;
  if strpos(definition,original)=0 then raise exception 'Unexpected file capabilities definition'; end if;
  definition := replace(definition,original,$new$if action='capabilities' then
    if reason is null and (used_month+held+20000000>1000000000 or used_year+held+20000000>5000000000) then
      reason:='quota_exceeded';
    end if;
    return jsonb_build_object$new$);
  execute definition;
end $quota_hold$;

create index pomodoist_uploads_quota_unreleased on private.pomodoist_uploads(quota_user_id)
  where storage_deleted_at is null and (finished_at is null or deleted_at is not null);
