-- One canonical object registry for personal and shared project/task files.
-- Object paths and quota attribution survive changes of access ownership.
alter table private.pomodoist_uploads
  alter column scope_id drop not null,
  alter column task_id drop not null,
  add column project_id text,
  add column personal_user_id uuid,
  add column quota_user_id uuid,
  add column storage_deleted_at timestamptz;
update private.pomodoist_uploads set quota_user_id=user_id;
alter table private.pomodoist_uploads
  alter column quota_user_id set not null,
  add constraint pomodoist_file_access_owner check (num_nonnulls(scope_id,personal_user_id)=1),
  add constraint pomodoist_file_target check (num_nonnulls(task_id,project_id)=1);
create index pomodoist_uploads_personal on private.pomodoist_uploads(personal_user_id) where deleted_at is null;
create index pomodoist_uploads_scope_target on private.pomodoist_uploads(scope_id,task_id,project_id) where deleted_at is null;
create index pomodoist_uploads_quota_pending on private.pomodoist_uploads(quota_user_id,expires_at) where finished_at is null and deleted_at is null;
alter table private.pomodoist_storage_deletions add column retain_until timestamptz not null default now();

-- This function never authorizes access: only the private dispatcher publishes.
create function private.pomodoist_file_publish(p_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare u private.pomodoist_uploads%rowtype; d jsonb; revision bigint;
begin
  select * into strict u from private.pomodoist_uploads where id=p_id;
  d:=jsonb_build_object('id',u.id,'scopeId',u.scope_id,'taskId',u.task_id,'projectId',u.project_id,
    'createdBy',u.user_id,'authorName',coalesce((select display_name from public.profiles where id=u.user_id),'Member'),
    'name',u.name,'contentType',u.content_type,'bytes',u.bytes,'createdAt',u.finished_at);
  if u.finished_at is null then return d; end if;
  if u.scope_id is not null then
    perform private.pomodoist_shared_put(u.scope_id,'attachment',u.id::text,d,u.deleted_at);
    perform private.pomodoist_collaboration_hint(u.scope_id);
    select server_revision into revision from private.pomodoist_shared_entities
      where scope_id=u.scope_id and entity_type='attachment' and entity_id=u.id::text;
  else
    insert into public.sync_entities(user_id,app_id,entity_type,entity_id,server_revision,client_updated_at,deleted_at,data,created_at,updated_at)
      values(u.personal_user_id,'pomodoist','attachment',u.id::text,nextval('public.sync_revision_seq'),now(),u.deleted_at,d,now(),now())
      on conflict(user_id,app_id,entity_type,entity_id) do update
      set server_revision=excluded.server_revision,client_updated_at=now(),deleted_at=excluded.deleted_at,data=excluded.data,updated_at=now()
      returning server_revision into revision;
  end if;
  return d||jsonb_build_object('serverRevision',revision);
end $$;
revoke all on function private.pomodoist_file_publish(uuid) from public,anon,authenticated;

create function private.pomodoist_file_delete(p_id uuid) returns void
language plpgsql security definer set search_path='' as $$
declare u private.pomodoist_uploads%rowtype;
begin
  perform pg_advisory_xact_lock(hashtextextended('pomodoist-file-lifecycle',0));
  select * into u from private.pomodoist_uploads where id=p_id for update;
  if not found or u.deleted_at is not null then return; end if;
  if u.finished_at is not null then
    update private.pomodoist_upload_years set bytes=bytes-u.bytes
      where user_id=u.quota_user_id and year=extract(year from u.finished_at at time zone 'UTC')::integer;
  end if;
  update private.pomodoist_uploads set deleted_at=now() where id=p_id;
  insert into private.pomodoist_storage_deletions(object_path,retain_until)
    values(u.object_path,greatest(now(),u.expires_at + interval '2 hours' + interval '5 minutes'))
    on conflict(object_path) do update set retain_until=greatest(pomodoist_storage_deletions.retain_until,excluded.retain_until);
  perform private.pomodoist_file_publish(p_id);
end $$;
revoke all on function private.pomodoist_file_delete(uuid) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION private.pomodoist_files(p_request jsonb) returns jsonb
language plpgsql security definer set search_path='' set timezone='UTC' as $$
declare
  actor uuid:=auth.uid(); action text:=p_request->>'action'; scope uuid; owner_id uuid; payer uuid;
  role_name text; task text; project text; target_id text; target_type text; target_data jsonb; target_deleted timestamptz;
  u private.pomodoist_uploads%rowtype; amount bigint; actual_size bigint; actual_type text;
  month_start date:=date_trunc('month',now() at time zone 'UTC')::date;
  yr integer:=extract(year from now() at time zone 'UTC')::integer;
  used_month bigint; used_year bigint; held bigint; storage_ready boolean:=false; editable boolean; reason text;
begin
  if jsonb_typeof(p_request) is distinct from 'object' or octet_length(p_request::text)>1000000
    or action is null or action not in ('capabilities','reserveUpload','finishUpload','download','deleteAttachment') then
    raise exception using errcode='22023',message='Invalid file request';
  end if;
  -- ponytail: serialize file lifecycle and related content mutations; use ordered
  -- per-owner/payer locks if measured concurrent file traffic needs more throughput.
  perform pg_advisory_xact_lock(hashtextextended('pomodoist-file-lifecycle',0));
  if actor is null or not exists(select 1 from auth.users where id=actor and not coalesce(is_anonymous,false))
    or not exists(select 1 from auth.sessions where user_id=actor and id::text=auth.jwt()->>'session_id'
      and (not_after is null or not_after>now())) then
    raise exception using errcode='42501',message='An active authenticated session is required';
  end if;
  if p_request ? 'objectPath' or p_request ? 'quotaUserId' or p_request ? 'personalUserId' then
    raise exception using errcode='22023',message='File ownership is server controlled';
  end if;
  if action in ('finishUpload','download','deleteAttachment') then
    select * into u from private.pomodoist_uploads where id=
      (case when action='finishUpload' then p_request->>'uploadId' else p_request->>'attachmentId' end)::uuid for update;
    if not found then raise exception using errcode='42501',message='Attachment is inaccessible'; end if;
    scope:=u.scope_id; task:=u.task_id; project:=u.project_id; owner_id:=u.personal_user_id;
    if nullif(p_request->>'scopeId','') is not null and scope is distinct from (p_request->>'scopeId')::uuid then
      raise exception using errcode='42501',message='Attachment is inaccessible'; end if;
  else
    scope:=nullif(p_request->>'scopeId','')::uuid;
    task:=nullif(p_request->>'taskId',''); project:=nullif(p_request->>'projectId','');
    if num_nonnulls(task,project)<>1 or length(coalesce(task,project))>200 then
      raise exception using errcode='22023',message='Exactly one file target is required'; end if;
    if scope is null then owner_id:=actor; end if;
  end if;
  if scope is not null then
    select s.owner_id,m.role into owner_id,role_name from private.pomodoist_scopes s
      join private.pomodoist_members m on m.scope_id=s.id and m.user_id=actor where s.id=scope for update of s;
    if not found then raise exception using errcode='42501',message='Shared scope is inaccessible'; end if;
  else
    if owner_id is distinct from actor then raise exception using errcode='42501',message='Attachment is inaccessible'; end if;
    role_name:='administrator';
  end if;
  editable:=role_name in ('administrator','member');
  if u.id is not null and u.deleted_at is not null then
    if action='deleteAttachment' and editable then return jsonb_build_object('ok',true); end if;
    raise exception using errcode='42501',message='Attachment is inaccessible';
  end if;
  target_type:=case when task is not null then 'task' else 'project' end;
  target_id:=coalesce(task,project);
  if scope is null then
    select data,deleted_at into target_data,target_deleted from public.sync_entities
      where user_id=actor and app_id='pomodoist' and entity_type=target_type and entity_id=target_id;
  else
    select data,deleted_at into target_data,target_deleted from private.pomodoist_shared_entities
      where scope_id=scope and entity_type=target_type and entity_id=target_id;
  end if;
  if target_data is null or target_data='{}'::jsonb
    or (target_deleted is not null and action not in ('download','deleteAttachment')) then
    raise exception using errcode='42501',message='File target is inaccessible';
  end if;
  if action='download' then
    if u.finished_at is null then raise exception using errcode='42501',message='Attachment is unfinished'; end if;
    return jsonb_build_object('objectPath',u.object_path,'name',u.name,'attachmentId',u.id,'contentType',u.content_type);
  elsif action='deleteAttachment' then
    if not editable then raise exception using errcode='42501',message='Editor role required'; end if;
    perform private.pomodoist_file_delete(u.id);
    return jsonb_build_object('ok',true);
  elsif action='finishUpload' and u.finished_at is not null then
    if u.user_id<>actor then raise exception using errcode='42501',message='Upload author required'; end if;
    return jsonb_build_object('attachment',private.pomodoist_file_publish(u.id));
  end if;
  -- Select the payer once; full personal quota never silently spills to the owner.
  payer:=case when public.has_active_pomodoist_paid_entitlement(actor) then actor
    when scope is not null and public.has_active_pomodoist_paid_entitlement(owner_id) then owner_id else null end;
  if action='finishUpload' then payer:=u.quota_user_id; end if;
  if to_regclass('storage.objects') is not null and to_regclass('storage.buckets') is not null then
    execute 'select exists(select 1 from storage.buckets where id=''pomodoist-shared'' and not public)' into storage_ready;
  end if;
  reason:=case when not editable then 'read_only' when payer is null then 'pro_required'
    when not storage_ready then 'storage_unavailable' else null end;
  select coalesce((select bytes from private.pomodoist_upload_months where user_id=payer and month=month_start),0) into used_month;
  select coalesce((select bytes from private.pomodoist_upload_years where user_id=payer and year=yr),0) into used_year;
  select coalesce(sum(bytes),0) into held from private.pomodoist_uploads where quota_user_id=payer
    and finished_at is null and deleted_at is null and expires_at>now() and (u.id is null or id<>u.id);
  if action='capabilities' then
    return jsonb_build_object('canUpload',reason is null,'canDelete',editable,'reason',reason,
      'maxFileBytes',20000000,'monthlyLimitBytes',1000000000,'yearlyLimitBytes',5000000000,
      'monthlyUsedBytes',used_month,'yearlyUsedBytes',used_year,'reservedBytes',held);
  end if;
  if not editable then raise exception using errcode='42501',message='Editor role required'; end if;
  if payer is null or not public.has_active_pomodoist_paid_entitlement(payer) then
    raise exception using errcode='42501',message='Pro subscription required'; end if;
  if not storage_ready then raise exception using errcode='55000',message='File storage is unavailable'; end if;
  if action='reserveUpload' then
    amount:=(p_request->>'bytes')::bigint;
    if amount is null or amount not between 1 and 20000000
      or length(coalesce(p_request->>'name','')) not between 1 and 255
      or p_request->>'name' ~ '[[:cntrl:]/\\]'
      or length(coalesce(p_request->>'contentType','')) not between 1 and 200
      or p_request->>'contentType' !~ '^[a-zA-Z0-9!#$&^_.+-]+/[a-zA-Z0-9!#$&^_.+-]+$' then
      raise exception using errcode='22023',message='Invalid attachment'; end if;
    select * into u from private.pomodoist_uploads where id=(p_request->>'uploadId')::uuid for update;
    if found then
      if u.user_id<>actor or u.scope_id is distinct from scope or u.personal_user_id is distinct from (case when scope is null then actor else null end)
        or u.task_id is distinct from task or u.project_id is distinct from project or u.bytes<>amount
        or u.name<>p_request->>'name' or u.content_type<>p_request->>'contentType' or u.deleted_at is not null
        or (u.finished_at is null and u.expires_at<=now()) then
        raise exception using errcode='22023',message='Upload ID is unavailable'; end if;
      if u.finished_at is null and not public.has_active_pomodoist_paid_entitlement(u.quota_user_id) then
        raise exception using errcode='42501',message='Original upload quota account requires Pro'; end if;
    else
      if used_month+held+amount>1000000000 or used_year+held+amount>5000000000 then
        raise exception using errcode='54000',message='Attachment quota exceeded'; end if;
      insert into private.pomodoist_uploads(id,scope_id,personal_user_id,task_id,project_id,user_id,quota_user_id,name,content_type,bytes,object_path)
        values((p_request->>'uploadId')::uuid,scope,case when scope is null then actor else null end,task,project,actor,payer,
          p_request->>'name',p_request->>'contentType',amount,'files/'||actor::text||'/'||(p_request->>'uploadId')) returning * into u;
    end if;
    return jsonb_build_object('uploadId',u.id,'objectPath',u.object_path,'expiresAt',u.expires_at,'finished',u.finished_at is not null);
  end if;
  if u.user_id<>actor or u.expires_at<=now() then
    raise exception using errcode='42501',message='Upload reservation is inaccessible or expired'; end if;
  execute 'select (metadata->>''size'')::bigint,metadata->>''mimetype'' from storage.objects where bucket_id=''pomodoist-shared'' and name=$1'
    into actual_size,actual_type using u.object_path;
  if actual_size is null then
    raise exception using errcode='P0002',message='Uploaded object is not present'; end if;
  if actual_size is distinct from u.bytes or actual_type is distinct from u.content_type then
    raise exception using errcode='22023',message='Uploaded object does not match reservation'; end if;
  if used_month+held+u.bytes>1000000000 or used_year+held+u.bytes>5000000000 then
    raise exception using errcode='54000',message='Attachment quota exceeded for completion period'; end if;
  insert into private.pomodoist_upload_months(user_id,month,bytes) values(payer,month_start,u.bytes)
    on conflict(user_id,month) do update set bytes=pomodoist_upload_months.bytes+excluded.bytes;
  insert into private.pomodoist_upload_years(user_id,year,bytes) values(payer,yr,u.bytes)
    on conflict(user_id,year) do update set bytes=pomodoist_upload_years.bytes+excluded.bytes;
  update private.pomodoist_uploads set finished_at=now() where id=u.id;
  return jsonb_build_object('attachment',private.pomodoist_file_publish(u.id));
end $$;
revoke all on function private.pomodoist_files(jsonb) from public,anon;
grant execute on function private.pomodoist_files(jsonb) to authenticated,service_role;
create function public.pomodoist_files(p_request jsonb) returns jsonb
language sql set search_path='' as $$ select private.pomodoist_files(p_request); $$;
revoke all on function public.pomodoist_files(jsonb) from public,anon;
grant execute on function public.pomodoist_files(jsonb) to authenticated,service_role;

-- Move access, not bytes. Pending upload reservations keep their author/payer.
create function private.pomodoist_files_share(p_scope uuid,p_actor uuid,p_projects text[],p_tasks text[]) returns void
language plpgsql security definer set search_path='' as $$
declare u record;
begin
  for u in select * from private.pomodoist_uploads where personal_user_id=p_actor and deleted_at is null
    and (project_id=any(p_projects) or task_id=any(p_tasks)) for update loop
    update public.sync_entities set deleted_at=now(),updated_at=now(),server_revision=nextval('public.sync_revision_seq')
      where user_id=p_actor and app_id='pomodoist' and entity_type='attachment' and entity_id=u.id::text;
    -- Retain transfer tombstones beyond the ordinary personal 90-day window.
    insert into private.pomodoist_transferred_entities(user_id,entity_type,entity_id,scope_id)
      values(p_actor,'attachment',u.id::text,p_scope) on conflict do nothing;
    update private.pomodoist_uploads set scope_id=p_scope,personal_user_id=null where id=u.id;
    perform private.pomodoist_file_publish(u.id);
  end loop;
end $$;
revoke all on function private.pomodoist_files_share(uuid,uuid,text[],text[]) from public,anon,authenticated;

-- Content deletion hooks do not delete task files on soft task deletion: task
-- history retains them until its ordinary retention policy removes the content.
create function private.pomodoist_files_content_deleted() returns trigger
language plpgsql security definer set search_path='' as $$
declare u record; personal uuid; scope uuid; typ text; eid text; removed boolean;
begin
  if TG_TABLE_NAME='sync_entities' then
    if old.app_id<>'pomodoist' then return null; end if;
  end if;
  typ:=old.entity_type; eid:=old.entity_id;
  if typ not in ('project','task') then return null; end if;
  removed:=TG_OP='DELETE';
  if not removed then
    removed:=(typ='project' and old.deleted_at is null and new.deleted_at is not null)
      or (typ='task' and old.data<>'{}'::jsonb and new.data='{}'::jsonb);
  end if;
  if not removed then return null; end if;
  if TG_TABLE_NAME='sync_entities' then personal:=old.user_id; else scope:=old.scope_id; end if;
  for u in select id from private.pomodoist_uploads where deleted_at is null
    and personal_user_id is not distinct from personal and scope_id is not distinct from scope
    and (case when typ='project' then project_id=eid else task_id=eid end) loop
    perform private.pomodoist_file_delete(u.id);
  end loop;
  return null;
end $$;
revoke all on function private.pomodoist_files_content_deleted() from public,anon,authenticated;
create trigger pomodoist_personal_file_target_deleted after update or delete on public.sync_entities
  for each row execute function private.pomodoist_files_content_deleted();
create trigger pomodoist_shared_file_target_deleted after update or delete on private.pomodoist_shared_entities
  for each row execute function private.pomodoist_files_content_deleted();

-- Auth deletion preserves shared files authored/sponsored by this account.
-- Personal files have no remaining recipient and are queued before user removal.
create function private.pomodoist_files_account_deleted() returns trigger
language plpgsql security definer set search_path='' as $$
declare u record;
begin
  perform pg_advisory_xact_lock(hashtextextended('pomodoist-file-lifecycle',0));
  for u in select id from private.pomodoist_uploads where personal_user_id=old.id and deleted_at is null loop
    perform private.pomodoist_file_delete(u.id);
  end loop;
  return old;
end $$;
revoke all on function private.pomodoist_files_account_deleted() from public,anon,authenticated;
create trigger pomodoist_files_account_deleted before delete on auth.users
  for each row execute function private.pomodoist_files_account_deleted();

CREATE OR REPLACE FUNCTION private.pomodoist_collaboration_storage_cleanup(p_deleted text[] default array[]::text[]) returns jsonb
language plpgsql security definer set search_path='' as $$
declare u record;
begin
  if coalesce(current_setting('request.jwt.claims',true),'{}')::jsonb->>'role' is distinct from 'service_role' then
    raise exception using errcode='42501',message='Service role required'; end if;
  perform pg_advisory_xact_lock(hashtextextended('pomodoist-file-lifecycle',0));
  for u in select id from private.pomodoist_uploads
    where finished_at is null and expires_at<=now() and deleted_at is null loop
    perform private.pomodoist_file_delete(u.id);
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

create function private.invoke_pomodoist_files_cleanup() returns bigint
language plpgsql security definer set search_path='' as $$
declare address text; secret text; request_id bigint;
begin
  if not exists(select 1 from private.pomodoist_storage_deletions)
    and not exists(select 1 from private.pomodoist_uploads where finished_at is null and deleted_at is null and expires_at<=now()) then return null; end if;
  select decrypted_secret into address from vault.decrypted_secrets where name='pomodoist-files-cleanup-url' order by updated_at desc limit 1;
  select decrypted_secret into secret from vault.decrypted_secrets where name='pomodoist-files-cleanup-secret' order by updated_at desc limit 1;
  if coalesce(address,'')='' or coalesce(secret,'')='' then return null; end if;
  select net.http_post(url:=address,body:='{}'::jsonb,
    headers:=jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||secret),
    timeout_milliseconds:=55000) into request_id;
  return request_id;
end $$;
revoke all on function private.invoke_pomodoist_files_cleanup() from public,anon,authenticated;
select cron.schedule('pomodoist-files-cleanup','*/5 * * * *','select private.invoke_pomodoist_files_cleanup();');

CREATE OR REPLACE FUNCTION private.pomodoist_collaboration(p_request jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    SET "TimeZone" TO 'UTC'
    AS $_$
declare
  actor uuid:=auth.uid(); action text:=p_request->>'action'; scope uuid; role_name text;
  s private.pomodoist_scopes%rowtype; invitation private.pomodoist_invitations%rowtype;
  upload private.pomodoist_uploads%rowtype; rec record; result jsonb; d jsonb; rows jsonb;
  applied jsonb:='[]'; conflicts jsonb:='[]'; rejected jsonb:='[]'; operation jsonb; receipt record;
  target uuid; ids text[]; task_ids text[]; token text; since bigint; cursor_value bigint; more boolean;
  paid boolean; amount bigint; held bigint; used_month bigint; used_year bigint; month_start date; yr integer; object_size bigint;
begin
  perform pg_advisory_xact_lock(hashtextextended('pomodoist-file-lifecycle',0));
  if action in ('reserveUpload','finishUpload','download','deleteAttachment') then
    return private.pomodoist_files(p_request);
  end if;
  if octet_length(p_request::text)>1000000 then raise exception using errcode='22023',message='Request is too large'; end if;
  if jsonb_typeof(p_request) is distinct from 'object' then raise exception using errcode='22023',message='Expected request object'; end if;
  if action='publicRead' then
    select * into s from private.pomodoist_scopes where public_token=p_request->>'token' and length(p_request->>'token')=64;
    if not found then raise exception using errcode='42501',message='Public link is unavailable'; end if;
    select coalesce(jsonb_agg(jsonb_build_object('id',entity_id,'entityType',entity_type,
      'data',(select coalesce(jsonb_object_agg(k,v),'{}') from jsonb_each(e.data) a(k,v)
        where k in ('name','content','description','parentId','projectId','taskId','body','dueJson','deadlineJson','status','priority','orderKey','createdAt','updatedAt','completedAt'))
        ||jsonb_build_object('creatorName',coalesce((select display_name from public.profiles where id::text=e.data->>'createdBy'),'Member'),
          'assigneeNames',coalesce((select jsonb_agg(coalesce(p.display_name,'Member')) from public.profiles p
            where p.id::text in(select jsonb_array_elements_text(coalesce(e.data->'assigneeIds','[]')))),'[]')))
      order by e.server_revision),'[]') into rows from private.pomodoist_shared_entities e
      where scope_id=s.id and entity_type in ('project','task','comment') and deleted_at is null
      and (entity_type<>'comment' or exists(select 1 from private.pomodoist_shared_entities t where t.scope_id=s.id
        and t.entity_type='task' and t.entity_id=e.data->>'taskId' and t.deleted_at is null));
    return jsonb_build_object('scopeId',s.id,'rootProjectId',s.root_project_id,'entities',rows);
  end if;
  -- Deleted users and revoked sessions must not retain access through unexpired JWTs.
  if actor is null or not exists(select 1 from auth.users where id=actor and not coalesce(is_anonymous,false))
    or not exists(select 1 from auth.sessions where user_id=actor and id::text=auth.jwt()->>'session_id'
      and (not_after is null or not_after>now())) then
    raise exception using errcode='42501',message='An active authenticated session is required';
  end if;
  if action in ('state','notifications') then
    for rec in select scope_id from private.pomodoist_members where user_id=actor loop
      perform private.pomodoist_history_refresh(rec.scope_id);
    end loop;
    perform private.pomodoist_history_refresh(null,actor);
    select coalesce(jsonb_agg(jsonb_build_object('id',id,'scopeId',scope_id,'kind',kind,'data',data,'readAt',read_at,'createdAt',created_at)
      order by created_at desc),'[]') into rows from (select * from private.pomodoist_notifications where user_id=actor order by created_at desc limit 200) n;
    if action='notifications' then return jsonb_build_object('notifications',rows); end if;
    return jsonb_build_object('userId',actor,'scopes',coalesce((select jsonb_agg(private.pomodoist_scope_json(scope_id,actor))
      from private.pomodoist_members where user_id=actor),'[]'),'notifications',rows,
      'preferences',private.pomodoist_preferences_json(actor),
      'invitations',coalesce((select jsonb_agg(jsonb_build_object('id',i.id,'scopeId',i.scope_id,'role',i.role,'token',i.token,'expiresAt',i.expires_at))
        from private.pomodoist_invitations i join auth.users u on lower(u.email)=i.email where u.id=actor
        and u.email_confirmed_at is not null and i.revoked_at is null and i.accepted_at is null and i.expires_at>now()),'[]'),
      'personalHistory',(select jsonb_build_object('historyUnlimited',history_unlimited,'graceEndsAt',grace_ends_at)
        from private.pomodoist_personal_history where user_id=actor),
      'personalRevision',coalesce((select max(server_revision) from public.sync_entities where user_id=actor and app_id='pomodoist'),0));
  elsif action='readNotification' then
    update private.pomodoist_notifications set read_at=coalesce(read_at,now()) where id=(p_request->>'notificationId')::uuid and user_id=actor;
    return jsonb_build_object('ok',true);
  elsif action='share' then
    perform pg_advisory_xact_lock(hashtextextended('pomodoist-google-calendar:'||actor::text,0));
    if p_request->>'rootProjectId'='inbox' then raise exception using errcode='22023',message='Inbox cannot be shared'; end if;
    select coalesce(max(server_revision),0) into cursor_value from public.sync_entities where user_id=actor and app_id='pomodoist';
    if p_request->>'expectedRevision' is null or (p_request->>'expectedRevision')::bigint<>cursor_value then
      raise exception using errcode='22023',message='Complete personal sync before sharing'; end if;
    if not exists(select 1 from public.sync_entities where user_id=actor and app_id='pomodoist' and entity_type='project'
      and entity_id=p_request->>'rootProjectId' and deleted_at is null) then raise exception using errcode='22023',message='Personal project not found'; end if;
    with recursive tree as (
      select entity_id from public.sync_entities where user_id=actor and app_id='pomodoist' and entity_type='project' and entity_id=p_request->>'rootProjectId' and deleted_at is null
      union select e.entity_id from public.sync_entities e join tree t on e.data->>'parentId'=t.entity_id
        where e.user_id=actor and e.app_id='pomodoist' and e.entity_type='project' and e.deleted_at is null)
    select array_agg(entity_id) into ids from tree;
    if exists(select 1 from public.sync_entities e join private.pomodoist_transferred_entities t on t.user_id=e.user_id
      and t.entity_type=e.entity_type and t.entity_id=e.entity_id where e.user_id=actor and e.app_id='pomodoist'
      and e.entity_type='project' and e.data->>'parentId'=any(ids)) then
      raise exception using errcode='22023',message='A shared root cannot contain another shared root'; end if;
    select array_agg(entity_id) into task_ids from public.sync_entities where user_id=actor and app_id='pomodoist'
      and entity_type='task' and data->>'projectId'=any(ids);
    insert into private.pomodoist_scopes(root_project_id,owner_id) values(p_request->>'rootProjectId',actor) returning * into s;
    insert into private.pomodoist_members(scope_id,user_id,role) values(s.id,actor,'administrator');
    perform private.pomodoist_files_share(s.id,actor,ids,task_ids);
    insert into private.pomodoist_shared_preferences(scope_id,user_id,entity_type,entity_id,data)
      select s.id,actor,'scope',s.id::text,jsonb_build_object('rootParentId',data->'parentId') from public.sync_entities
      where user_id=actor and app_id='pomodoist' and entity_type='project' and entity_id=s.root_project_id;
    for rec in select * from public.sync_entities where user_id=actor and app_id='pomodoist'
      and ((entity_type='project' and entity_id=any(ids)) or (entity_type='task' and entity_id=any(task_ids))) loop
      insert into private.pomodoist_shared_preferences(scope_id,user_id,entity_type,entity_id,data)
        values(s.id,actor,rec.entity_type,case when rec.entity_type='label' then s.id::text||':'||rec.entity_id else rec.entity_id end,
          (select coalesce(jsonb_object_agg(key,value),'{}') from jsonb_each(rec.data) where key in ('isFavorite','isCollapsed','dayOrder','viewStyle','viewPreferences','reminders')))
        on conflict(scope_id,user_id,entity_type,entity_id) do nothing;
      d:=(rec.data-array['userId','dayOrder','isCollapsed','isFavorite','reminderJson','reminders','viewPreferences','viewStyle','completedFocusIntervals','totalFocusSeconds'])
        ||jsonb_build_object('scopeId',s.id,'createdBy',coalesce(rec.data->>'createdBy',actor::text));
      if rec.entity_type='project' and rec.entity_id=s.root_project_id then d:=d||jsonb_build_object('parentId',null); end if;
      if rec.entity_type='task' then
        d:=d||jsonb_build_object('assigneeIds','[]'::jsonb,'completedBy',case when d->>'status'='completed' then actor else null end);
        if d->>'parentId' is not null and not(d->>'parentId'=any(coalesce(task_ids,array[]::text[]))) then d:=d||jsonb_build_object('parentId',null); end if;
      end if;
      perform private.pomodoist_shared_put(s.id,rec.entity_type,rec.entity_id,d,rec.deleted_at);
      update public.sync_entities set deleted_at=coalesce(deleted_at,now()),server_revision=nextval('public.sync_revision_seq'),updated_at=now()
        where user_id=actor and app_id='pomodoist' and entity_type=rec.entity_type and entity_id=rec.entity_id;
      insert into private.pomodoist_transferred_entities values(actor,rec.entity_type,rec.entity_id,s.id);
    end loop;
    for rec in select * from public.sync_entities where user_id=actor and app_id='pomodoist' and deleted_at is null
      and ((entity_type='section' and data->>'projectId'=any(ids))
        or (entity_type in ('task_label','task_kanban_status','task_completion') and data->>'taskId'=any(task_ids))
        or (entity_type='focus_interval' and data->>'taskId'=any(task_ids) and data->>'type'='work' and data->>'status'='completed')
        or (entity_type='label' and entity_id in(select data->>'labelId' from public.sync_entities where user_id=actor
          and app_id='pomodoist' and entity_type in ('task_label','task_kanban_status') and data->>'taskId'=any(task_ids))) or (entity_type='label' and data->>'kind'='kanbanStatus')) loop
      insert into private.pomodoist_shared_preferences(scope_id,user_id,entity_type,entity_id,data)
        values(s.id,actor,rec.entity_type,case when rec.entity_type='label' then s.id::text||':'||rec.entity_id else rec.entity_id end,
          (select coalesce(jsonb_object_agg(key,value),'{}') from jsonb_each(rec.data) where key in ('isFavorite','isCollapsed','dayOrder','viewStyle','viewPreferences','reminders')))
        on conflict(scope_id,user_id,entity_type,entity_id) do nothing;
      d:=(rec.data-array['userId','dayOrder','isCollapsed','isFavorite'])||jsonb_build_object('scopeId',s.id,'createdBy',actor);
      if rec.entity_type in ('task_completion','focus_interval') then d:=d||jsonb_build_object('userId',actor); end if;
      if rec.entity_type='focus_interval' then
        d:=d||jsonb_build_object('durationSeconds',coalesce((d->>'durationSeconds')::integer,(d->>'plannedSeconds')::integer));
      end if;
      if rec.entity_type='label' then
        d:=d||jsonb_build_object('id',s.id::text||':'||rec.entity_id);
        perform private.pomodoist_shared_put(s.id,'label',s.id::text||':'||rec.entity_id,d);
      elsif rec.entity_type in ('task_label','task_kanban_status') then
        d:=d||jsonb_build_object('labelId',s.id::text||':'||(rec.data->>'labelId'));
        d:=d||jsonb_build_object('id',case when rec.entity_type='task_label'
          then (d->>'taskId')||':'||(d->>'labelId') else rec.entity_id end);
        perform private.pomodoist_shared_put(s.id,rec.entity_type,
          case when rec.entity_type='task_label' then (d->>'taskId')||':'||(d->>'labelId') else rec.entity_id end,d);
      else perform private.pomodoist_shared_put(s.id,rec.entity_type,rec.entity_id,d); end if;
      if rec.entity_type not in ('label','focus_interval') then
        update public.sync_entities set deleted_at=now(),server_revision=nextval('public.sync_revision_seq'),updated_at=now()
          where user_id=actor and app_id='pomodoist' and entity_type=rec.entity_type and entity_id=rec.entity_id;
        insert into private.pomodoist_transferred_entities values(actor,rec.entity_type,rec.entity_id,s.id);
      end if;
    end loop;
    for rec in select * from private.pomodoist_shared_entities where scope_id=s.id and entity_type='task' loop
      select jsonb_build_object('totalFocusSeconds',coalesce(sum(coalesce((data->>'durationSeconds')::bigint,(data->>'plannedSeconds')::bigint)),0),
        'completedFocusIntervals',count(*)) into d from private.pomodoist_shared_entities where scope_id=s.id and entity_type='focus_interval'
        and data->>'taskId'=rec.entity_id and deleted_at is null and data->>'type'='work' and data->>'status'='completed';
      perform private.pomodoist_shared_put(s.id,'task',rec.entity_id,rec.data||d,rec.deleted_at);
    end loop;
    perform private.pomodoist_history_refresh(s.id);
    perform private.pomodoist_collaboration_event(s.id,actor,'shared',s.root_project_id);
    return jsonb_build_object('scope',private.pomodoist_scope_json(s.id,actor));
  elsif action='accept' then
    select i.scope_id into scope from private.pomodoist_invitations i where i.token=p_request->>'token';
  else scope:=(p_request->>'scopeId')::uuid;
  end if;
  select * into s from private.pomodoist_scopes where id=scope for update;
  if not found then raise exception using errcode='42501',message='Shared scope is inaccessible'; end if;
  if action='accept' then
    select i.* into invitation from private.pomodoist_invitations i where i.token=p_request->>'token' and i.scope_id=scope for update;
    if invitation.revoked_at is not null or invitation.expires_at<=now() or
      (invitation.email is not null and not exists(select 1 from auth.users where id=actor and lower(email)=invitation.email and email_confirmed_at is not null))
      or (invitation.accepted_by is not null and invitation.accepted_by<>actor) then
      raise exception using errcode='42501',message='Invitation is unavailable for this account'; end if;
    if exists(select 1 from private.pomodoist_members where scope_id=scope and user_id=actor) then
      return jsonb_build_object('scope',private.pomodoist_scope_json(scope,actor)); end if;
    insert into private.pomodoist_members(scope_id,user_id,role) values(scope,actor,invitation.role) on conflict do nothing;
    if invitation.email is not null then update private.pomodoist_invitations set accepted_by=actor,accepted_at=coalesce(accepted_at,now()) where id=invitation.id; end if;
    perform private.pomodoist_history_refresh(scope);
    perform private.pomodoist_collaboration_event(scope,actor,'member.joined',actor::text);
    return jsonb_build_object('scope',private.pomodoist_scope_json(scope,actor));
  end if;
  select role into role_name from private.pomodoist_members where scope_id=scope and user_id=actor;
  if role_name is null then raise exception using errcode='42501',message='Shared scope is inaccessible'; end if;
  perform private.pomodoist_history_refresh(scope);
  if action='preferences' then
    if coalesce(p_request->>'entityType','') not in ('scope','project','task','label','section')
      or coalesce(p_request->>'entityId','')='' or jsonb_typeof(p_request->'data') is distinct from 'object'
      or exists(select 1 from jsonb_object_keys(p_request->'data') k where k not in ('isFavorite','isCollapsed','dayOrder','reminders','viewStyle','viewPreferences','rootParentId')) then
      raise exception using errcode='22023',message='Invalid private preferences'; end if;
    if p_request->>'entityType'='scope' then
      if p_request->>'entityId'<>scope::text then raise exception using errcode='22023',message='Invalid scope preference identity'; end if;
    elsif not exists(select 1 from private.pomodoist_shared_entities where scope_id=scope and entity_type=p_request->>'entityType'
      and entity_id=p_request->>'entityId' and deleted_at is null) then raise exception using errcode='42501',message='Preference entity is inaccessible'; end if;
    if p_request->'data' ? 'rootParentId' then
      if p_request->>'entityType'<>'scope' then raise exception using errcode='22023',message='Root placement is a scope preference'; end if;
      if p_request->'data'->>'rootParentId' is not null and not exists(select 1 from public.sync_entities where user_id=actor and app_id='pomodoist'
        and entity_type='project' and entity_id=p_request->'data'->>'rootParentId' and deleted_at is null) then
        raise exception using errcode='22023',message='Root parent must be an accessible personal project'; end if;
    end if;
    insert into private.pomodoist_shared_preferences(scope_id,user_id,entity_type,entity_id,data)
      values(scope,actor,p_request->>'entityType',p_request->>'entityId',p_request->'data')
      on conflict(scope_id,user_id,entity_type,entity_id) do update
      set data=private.pomodoist_shared_preferences.data||excluded.data,updated_at=now();
    perform private.pomodoist_collaboration_hint(null,actor);
    return jsonb_build_object('preferences',private.pomodoist_preferences_json(actor,scope));
  end if;
  if action='members' then return jsonb_build_object('members',private.pomodoist_members_json(scope),
    'invitations',case when role_name='administrator' then coalesce((select jsonb_agg(jsonb_build_object('id',id,'email',email,'role',role,'expiresAt',expires_at,'revokedAt',revoked_at,'acceptedAt',accepted_at))
      from private.pomodoist_invitations where scope_id=scope),'[]') else '[]'::jsonb end);
  elsif action in ('pull','export') then
    since:=coalesce((p_request->>'sinceRevision')::bigint,0);
    if since<0 then raise exception using errcode='22023',message='Invalid cursor'; end if;
    with page as (select * from private.pomodoist_shared_entities where scope_id=scope and server_revision>since order by server_revision limit 501),
      limited as (select * from page order by server_revision limit 500)
    select coalesce(jsonb_agg(jsonb_build_object('entityType',entity_type,'entityId',entity_id,'data',data,'serverRevision',server_revision,
      'deletedAt',deleted_at,'updatedAt',updated_at) order by server_revision),'[]'),coalesce(max(server_revision),s.revision),
      (select count(*)>500 from page) into rows,cursor_value,more from limited;
    return jsonb_build_object('changes',rows,'nextCursor',cursor_value,'hasMore',more,'members',private.pomodoist_members_json(scope),
      'scope',private.pomodoist_scope_json(scope,actor),'preferences',private.pomodoist_preferences_json(actor,scope));
  elsif action='push' then
    if jsonb_typeof(p_request->'operations') is distinct from 'array' or jsonb_array_length(p_request->'operations')>200 then
      raise exception using errcode='22023',message='Expected at most 200 operations'; end if;
    for operation in select value from jsonb_array_elements(p_request->'operations') loop
      begin
        select stored.request,stored.result into receipt from private.pomodoist_shared_receipts stored
          where stored.scope_id=scope and stored.user_id=actor and stored.op_id=operation->>'opId';
        if found then
          if receipt.request<>operation then raise exception using errcode='22023',message='Operation ID was reused with different content'; end if;
          result:=receipt.result;
        else
          result:=private.pomodoist_shared_apply(scope,actor,role_name,operation);
          insert into private.pomodoist_shared_receipts values(scope,actor,operation->>'opId',operation,result);
        end if;
      exception when others then result:=jsonb_build_object('opId',operation->>'opId','status','rejected','code',sqlstate,'error',sqlerrm);
      end;
      if result->>'status'='applied' then applied:=applied||jsonb_build_array(result);
      elsif result->>'status'='conflict' then conflicts:=conflicts||jsonb_build_array(result);
      else rejected:=rejected||jsonb_build_array(result); end if;
    end loop;
    return jsonb_build_object('applied',applied,'conflicts',conflicts,'rejected',rejected);
  elsif action='unshare' and actor<>s.owner_id then
    raise exception using errcode='42501',message='Only the owner may make the project private';
  elsif action in ('invite','role','remove','transfer','delete','publicLink') and role_name<>'administrator' then
    raise exception using errcode='42501',message='Administrator role required';
  end if;
  if action='invite' then
    if p_request->>'invitationId' is not null and p_request->>'revoke'='true' then
      update private.pomodoist_invitations set revoked_at=coalesce(revoked_at,now()) where scope_id=scope and id=(p_request->>'invitationId')::uuid;
      return jsonb_build_object('ok',true);
    end if;
    if coalesce(p_request->>'role','member') not in ('member','observer') then raise exception using errcode='22023',message='Invitation role must be member or observer'; end if;
    if p_request->>'email' is not null and (length(p_request->>'email')>254 or (p_request->>'email')!~'^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$') then
      raise exception using errcode='22023',message='Invalid invitation email'; end if;
    if (select count(*) from private.pomodoist_invitations where scope_id=scope and created_at>now()-interval '1 hour')>=50 then
      raise exception using errcode='54000',message='Invitation rate limit exceeded'; end if;
    insert into private.pomodoist_invitations(scope_id,email,role,created_by)
      values(scope,lower(p_request->>'email'),coalesce(p_request->>'role','member'),actor) returning * into invitation;
    insert into private.pomodoist_notifications(user_id,scope_id,kind,data) select id,scope,'invitation',jsonb_build_object('invitationId',invitation.id)
      from auth.users where lower(email)=invitation.email;
    perform private.pomodoist_collaboration_event(scope,actor,'invitation.created',invitation.id::text);
    return jsonb_build_object('id',invitation.id,'token',invitation.token,'email',invitation.email,'role',invitation.role,'expiresAt',invitation.expires_at);
  elsif action in ('role','remove','leave','transfer') then
    target:=case when action='leave' then actor else (p_request->>'userId')::uuid end;
    if not exists(select 1 from private.pomodoist_members where scope_id=scope and user_id=target) then raise exception using errcode='22023',message='Member not found'; end if;
    if action='transfer' then
      if actor<>s.owner_id then raise exception using errcode='42501',message='Only the owner may transfer ownership'; end if;
      update private.pomodoist_members set role='administrator' where scope_id=scope and user_id=target;
      update private.pomodoist_scopes set owner_id=target where id=scope;
    else
      if target=s.owner_id then raise exception using errcode='42501',message='Owner must transfer ownership or delete the shared root'; end if;
      if action='role' then
        if coalesce(p_request->>'role','') not in ('administrator','member','observer') then raise exception using errcode='22023',message='Invalid role'; end if;
        update private.pomodoist_members set role=p_request->>'role' where scope_id=scope and user_id=target;
      else
        delete from private.pomodoist_members where scope_id=scope and user_id=target;
        delete from private.pomodoist_notifications where scope_id=scope and user_id=target;
      end if;
      if action<>'role' or p_request->>'role'='observer' then
        for rec in select * from private.pomodoist_shared_entities where scope_id=scope and entity_type='task' and data->'assigneeIds' ? target::text loop
          perform private.pomodoist_shared_put(scope,'task',rec.entity_id,rec.data||jsonb_build_object('assigneeIds',(rec.data->'assigneeIds')-target::text),rec.deleted_at);
        end loop;
      end if;
    end if;
    perform private.pomodoist_history_refresh(scope);
    perform private.pomodoist_collaboration_hint(scope,target);
    perform private.pomodoist_collaboration_event(scope,actor,'access.'||action,target::text);
    return jsonb_build_object('ok',true,'members',case when action='leave' then '[]'::jsonb else private.pomodoist_members_json(scope) end);
  elsif action='delete' then
    if actor<>s.owner_id then raise exception using errcode='42501',message='Only the owner may delete the shared root'; end if;
    for rec in select id from private.pomodoist_uploads where scope_id=scope and deleted_at is null loop
      perform private.pomodoist_file_delete(rec.id);
    end loop;
    -- Keep retired IDs/paths reserved while outstanding upload URLs and cleanup exist.
    update private.pomodoist_uploads set scope_id=null,personal_user_id=actor where scope_id=scope;
    perform private.pomodoist_collaboration_hint(scope);
    delete from private.pomodoist_scopes where id=scope;
    return jsonb_build_object('ok',true);
  elsif action='unshare' then
    delete from private.pomodoist_transferred_entities where scope_id=scope;
    -- Restore current content, including entities created after sharing. Keep
    -- scoped label identities so their relations remain valid without merging.
    for rec in select * from private.pomodoist_shared_entities where scope_id=scope
      and entity_type in ('project','task','section','label','task_label','task_kanban_status','task_completion') loop
      d:=(rec.data-array['scopeId','assigneeIds'])||jsonb_build_object('userId',actor);
      select coalesce(data,'{}'::jsonb) into result from private.pomodoist_shared_preferences
        where scope_id=scope and user_id=actor and entity_type=rec.entity_type and entity_id=rec.entity_id;
      d:=d||coalesce(result,'{}'::jsonb);
      if rec.entity_type='project' and rec.entity_id=s.root_project_id then
        select data->'rootParentId' into result from private.pomodoist_shared_preferences
          where scope_id=scope and user_id=actor and entity_type='scope' and entity_id=scope::text;
        d:=d||jsonb_build_object('parentId',result);
      end if;
      insert into public.sync_entities(user_id,app_id,entity_type,entity_id,server_revision,client_updated_at,deleted_at,data,created_at,updated_at)
        values(actor,'pomodoist',rec.entity_type,rec.entity_id,nextval('public.sync_revision_seq'),now(),rec.deleted_at,d,now(),now())
        on conflict(user_id,app_id,entity_type,entity_id) do update set deleted_at=excluded.deleted_at,
          server_revision=excluded.server_revision,updated_at=now(),client_updated_at=now(),data=excluded.data;
    end loop;
    for rec in select id from private.pomodoist_uploads where scope_id=scope loop
      update private.pomodoist_uploads set personal_user_id=actor, scope_id=null where id=rec.id;
      perform private.pomodoist_file_publish(rec.id);
    end loop;
    insert into private.pomodoist_notifications(user_id,scope_id,kind,data)
      select user_id,null,'access.unshare',jsonb_build_object('scopeId',scope) from private.pomodoist_members
      where scope_id=scope and user_id<>actor;
    perform private.pomodoist_collaboration_hint(scope);
    delete from private.pomodoist_scopes where id=scope;
    return jsonb_build_object('ok',true,'rootProjectId',s.root_project_id);
  elsif action='publicLink' then
    if jsonb_typeof(p_request->'enabled') is distinct from 'boolean' then raise exception using errcode='22023',message='Expected enabled boolean'; end if;
    token:=case when (p_request->>'enabled')::boolean then encode(extensions.gen_random_bytes(32),'hex') else null end;
    update private.pomodoist_scopes set public_token=token where id=scope;
    return jsonb_build_object('token',token);
  end if;
  raise exception using errcode='22023',message='Unknown collaboration action';
end $_$;


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
  perform pg_advisory_xact_lock(hashtextextended('pomodoist-file-lifecycle',0));
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
    if p_app_id = 'pomodoist' and v_entity_type = 'attachment' then
      raise exception using errcode='42501',message='Attachment metadata is server-authored';
    end if;
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


CREATE OR REPLACE FUNCTION public.prune_pomodoist_free_task_history() RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare r record; scope_rec record; deleted integer:=0; n integer; begin
  perform pg_advisory_xact_lock(hashtextextended('pomodoist-file-lifecycle',0));
  for r in select id from auth.users loop perform private.pomodoist_history_refresh(null,r.id); end loop;
  delete from public.sync_entities e using private.pomodoist_personal_history h
    where e.user_id=h.user_id and e.app_id='pomodoist' and e.entity_type='task' and not h.history_unlimited
      and not exists(select 1 from private.pomodoist_transferred_entities transferred where transferred.user_id=e.user_id
        and transferred.entity_type=e.entity_type and transferred.entity_id=e.entity_id)
      and (h.grace_ends_at is null or h.grace_ends_at<=now())
      and ((e.deleted_at is not null and e.deleted_at<now()-interval '365 days') or (e.data->>'status'='completed'
        and private.pomodoist_history_timestamp(e.data->>'completedAt',e.updated_at)<now()-interval '365 days'));
  get diagnostics deleted=row_count;
  for scope_rec in select id from private.pomodoist_scopes for update loop
    perform private.pomodoist_history_refresh(scope_rec.id);
    -- Retain tombstone identities and revisions permanently; remove aged content only.
    -- This permits every stale client to purge cached history without resurrection.
    for r in select e.* from private.pomodoist_shared_entities e join private.pomodoist_scopes s on s.id=e.scope_id
      where e.scope_id=scope_rec.id and e.entity_type='task' and e.data<>'{}'::jsonb and not s.history_unlimited
      and (s.grace_ends_at is null or s.grace_ends_at<=now())
      and ((e.deleted_at is not null and e.deleted_at<now()-interval '365 days') or (e.data->>'status'='completed'
        and private.pomodoist_history_timestamp(e.data->>'completedAt',e.updated_at)<now()-interval '365 days')) loop
      -- Earlier purges in this pass may already have promoted this task.
      select current_task.* into r from private.pomodoist_shared_entities current_task
        where current_task.scope_id=r.scope_id and current_task.entity_type='task' and current_task.entity_id=r.entity_id;
      declare surviving_child record; promoted_parent text; begin
        select parent.entity_id into promoted_parent from private.pomodoist_shared_entities parent
          where parent.scope_id=r.scope_id and parent.entity_type='task' and parent.entity_id=r.data->>'parentId'
            and parent.deleted_at is null and parent.data->>'projectId'=r.data->>'projectId';
        for surviving_child in select * from private.pomodoist_shared_entities where scope_id=r.scope_id and entity_type='task'
          and data->>'parentId'=r.entity_id and deleted_at is null loop
          perform private.pomodoist_shared_put(r.scope_id,'task',surviving_child.entity_id,
            surviving_child.data||jsonb_build_object('parentId',promoted_parent));
        end loop;
      end;
      delete from private.pomodoist_shared_receipts where scope_id=r.scope_id and request->>'entityId'=r.entity_id;
      perform private.pomodoist_shared_put(r.scope_id,'task',r.entity_id,'{}',coalesce(r.deleted_at,now()));
      deleted:=deleted+1;
      -- Task-associated records receive tombstones through the same revision sequence.
      declare child record; begin
        for child in select * from private.pomodoist_shared_entities where scope_id=r.scope_id and data->>'taskId'=r.entity_id loop
          delete from private.pomodoist_shared_receipts where scope_id=r.scope_id and request->>'entityType'=child.entity_type and request->>'entityId'=child.entity_id;
          perform private.pomodoist_shared_put(r.scope_id,child.entity_type,child.entity_id,'{}',now());
        end loop;
      end;
      perform private.pomodoist_collaboration_hint(r.scope_id);
    end loop;
  end loop;
  return deleted;
end $$;


-- These outer RPCs lock calendar jobs, command identities or Telegram accounts
-- before delegating to personal sync. Take the lifecycle lock first, preserving
-- their existing bodies and grants instead of copying unrelated implementations.
do $lock_order$
declare signature text; definition text; body_start integer;
begin
  foreach signature in array array[
    'public.pomodoist_google_calendar_service(text,uuid,jsonb)',
    'public.pomodoist_openclaw_action(uuid,uuid,uuid,uuid,text,text,bigint,jsonb,jsonb)',
    'public.push_pomodoist_draft_changes(text,text,jsonb)',
    'public.push_pomodoist_telegram_changes(bigint,uuid,uuid,jsonb)',
    'public.complete_pomodoist_telegram_link(bytea,uuid)'
  ] loop
    definition:=pg_get_functiondef(signature::regprocedure);
    body_start:=strpos(definition,E'\nbegin\n');
    if body_start=0 then raise exception 'Expected outer BEGIN in %',signature; end if;
    execute overlay(definition placing E'\nbegin\n  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(''pomodoist-file-lifecycle'',0));\n'
      from body_start for length(E'\nbegin\n'));
  end loop;
end $lock_order$;

-- A row trigger is too late: DELETE already holds the auth row lock, while
-- shared-file publication can hold lifecycle and wait on an auth foreign key.
create function private.pomodoist_files_account_delete_lock() returns trigger
language plpgsql security definer set search_path='' as $$
begin
  perform pg_advisory_xact_lock(hashtextextended('pomodoist-file-lifecycle',0));
  return null;
end $$;
revoke all on function private.pomodoist_files_account_delete_lock() from public,anon,authenticated;
create trigger pomodoist_files_account_delete_lock before delete on auth.users
  for each statement execute function private.pomodoist_files_account_delete_lock();

-- A device returning after the normal tombstone window must still discard
-- cached file metadata after deletion or transfer to another owner.
do $file_tombstones$
declare definition text; anchor text:=E'        deleted_at is null\n';
begin
  definition:=pg_get_functiondef('private.pull_changes(text,text,bigint,integer)'::regprocedure);
  if strpos(definition,anchor)=0 then raise exception 'Expected personal pull tombstone filter'; end if;
  execute replace(definition,anchor,anchor||E'        or (p_app_id = ''pomodoist'' and entity_type = ''attachment'')\n');
end $file_tombstones$;

notify pgrst, 'reload schema';
