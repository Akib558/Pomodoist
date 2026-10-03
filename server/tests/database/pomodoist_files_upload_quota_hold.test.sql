-- Real reservation/finalization calls; synthetic rows and metadata roll back.
-- No signed URLs, Storage uploads, or HTTP requests are made by this test.
begin;
\ir hosted-mode.inc
select plan(1);
-- A fresh DB-only test instance has no Storage service to provision this bucket.
insert into storage.buckets(id,name,public,file_size_limit)
  values('pomodoist-shared','pomodoist-shared',false,20000000)
  on conflict(id) do update set public=false,file_size_limit=20000000;
do $$
declare
  actor uuid:=gen_random_uuid(); session uuid:=gen_random_uuid(); first_upload uuid;
  upload_id uuid; result jsonb; object_path text;
  owner_id uuid:=gen_random_uuid(); shared_scope uuid:=gen_random_uuid();
begin
  insert into auth.users(id,email,aud,role,created_at,updated_at)
    values(actor,actor::text||'@example.test','authenticated','authenticated',now(),now());
  insert into auth.sessions(id,user_id,created_at,updated_at) values(session,actor,now(),now());
  insert into public.user_entitlements(user_id,app_id,entitlement_id,source,purchase_type,status)
    values(actor,'pomodoist','test:upload-quota','app_store','lifetime','active');
  insert into public.sync_entities(user_id,app_id,entity_type,entity_id,server_revision,client_updated_at,data)
    values(actor,'pomodoist','task','quota-test',nextval('public.sync_revision_seq'),now(),'{"content":"Quota test"}');
  perform set_config('request.jwt.claims',jsonb_build_object('sub',actor,'session_id',session,'role','authenticated')::text,true);

  for i in 1..50 loop
    upload_id:=gen_random_uuid();
    if i=1 then first_upload:=upload_id; end if;
    result:=public.pomodoist_files(jsonb_build_object('action','reserveUpload','taskId','quota-test',
      'uploadId',upload_id,'name','small.txt','contentType','text/plain','bytes',1));
    assert result->>'uploadId'=upload_id::text;
  end loop;
  result:=public.pomodoist_files('{"action":"capabilities","taskId":"quota-test"}');
  assert result->>'reservedBytes'='1000000000', 'Fifty one-byte declarations must hold 1 GB';
  assert result->>'canUpload'='false' and result->>'reason'='quota_exceeded';
  begin
    perform public.pomodoist_files(jsonb_build_object('action','reserveUpload','taskId','quota-test',
      'uploadId',gen_random_uuid(),'name','small.txt','contentType','text/plain','bytes',1));
    raise exception 'Expected the 51st one-byte reservation to fail';
  exception when sqlstate '54000' then null; end;
  -- An idempotent retry reuses its slot without double charging.
  perform public.pomodoist_files(jsonb_build_object('action','reserveUpload','taskId','quota-test',
    'uploadId',first_upload,'name','small.txt','contentType','text/plain','bytes',1));
  update private.pomodoist_uploads set expires_at=now()-interval '1 minute' where user_id=actor;
  perform private.pomodoist_file_delete(first_upload);
  result:=public.pomodoist_files('{"action":"capabilities","taskId":"quota-test"}');
  assert result->>'reservedBytes'='1000000000', 'Expiry and deletion must not release live capabilities';
  begin
    perform public.pomodoist_files(jsonb_build_object('action','reserveUpload','taskId','quota-test',
      'uploadId',gen_random_uuid(),'name','small.txt','contentType','text/plain','bytes',1));
    raise exception 'Expected expired/deleted reservations to keep their hold';
  exception when sqlstate '54000' then null; end;

  -- Exercise the real acknowledgement path: an early successful removal must
  -- retain its hold because the signed URL can still recreate the object.
  select u.object_path into object_path from private.pomodoist_uploads u where id=first_upload;
  perform set_config('request.jwt.claims','{"role":"service_role"}',true);
  perform private.pomodoist_collaboration_storage_cleanup(array[object_path]);
  assert (select storage_deleted_at is null from private.pomodoist_uploads where id=first_upload),
    'Early Storage acknowledgement must retain the reservation';
  -- Advance this fixture beyond the capability window, then acknowledge again.
  update private.pomodoist_uploads set expires_at=now()-interval '3 hours' where id=first_upload;
  update private.pomodoist_storage_deletions d set retain_until=now()-interval '1 minute'
    where d.object_path=(select u.object_path from private.pomodoist_uploads u where u.id=first_upload);
  perform private.pomodoist_collaboration_storage_cleanup(array[object_path]);
  assert (select storage_deleted_at is not null from private.pomodoist_uploads where id=first_upload),
    'Storage acknowledgement after capability expiry must release the reservation';
  perform set_config('request.jwt.claims',jsonb_build_object('sub',actor,'session_id',session,'role','authenticated')::text,true);
  result:=public.pomodoist_files('{"action":"capabilities","taskId":"quota-test"}');
  assert result->>'reservedBytes'='980000000', 'Only the confirmed slot must be released';

  -- Simulate a confirmed Storage deletion after all capabilities have expired.
  update private.pomodoist_uploads set deleted_at=now(),storage_deleted_at=now() where user_id=actor;
  result:=public.pomodoist_files('{"action":"capabilities","taskId":"quota-test"}');
  assert result->>'reservedBytes'='0' and result->>'canUpload'='true';
  upload_id:=gen_random_uuid();
  result:=public.pomodoist_files(jsonb_build_object('action','reserveUpload','taskId','quota-test',
    'uploadId',upload_id,'name','small.txt','contentType','text/plain','bytes',1));
  object_path:=result->>'objectPath';
  insert into storage.objects(bucket_id,name,metadata)
    values('pomodoist-shared',object_path,'{"size":20000000,"mimetype":"text/plain"}');
  begin
    perform public.pomodoist_files(jsonb_build_object('action','finishUpload','uploadId',upload_id));
    raise exception 'Expected the 1-byte declaration / 20 MB object mismatch to fail';
  exception when sqlstate '22023' then null; end;
  result:=public.pomodoist_files('{"action":"capabilities","taskId":"quota-test"}');
  assert result->>'reservedBytes'='20000000', 'Rejected finalization must retain the full hold';
  update storage.objects set metadata='{"size":1,"mimetype":"text/plain"}'
    where bucket_id='pomodoist-shared' and name=object_path;
  perform public.pomodoist_files(jsonb_build_object('action','finishUpload','uploadId',upload_id));
  perform public.pomodoist_files(jsonb_build_object('action','finishUpload','uploadId',upload_id));
  result:=public.pomodoist_files('{"action":"capabilities","taskId":"quota-test"}');
  assert result->>'reservedBytes'='0' and result->>'monthlyUsedBytes'='1' and result->>'yearlyUsedBytes'='1',
    'Successful completion replaces the hold with exact bytes, once';
  perform public.pomodoist_files(jsonb_build_object('action','deleteAttachment','attachmentId',upload_id));
  result:=public.pomodoist_files('{"action":"capabilities","taskId":"quota-test"}');
  assert result->>'reservedBytes'='20000000', 'Deletion must hold the slot until Storage confirms removal';
  update private.pomodoist_uploads set storage_deleted_at=now() where id=upload_id;

  update private.pomodoist_upload_months set bytes=980000001 where user_id=actor;
  begin
    perform public.pomodoist_files(jsonb_build_object('action','reserveUpload','taskId','quota-test',
      'uploadId',gen_random_uuid(),'name','small.txt','contentType','text/plain','bytes',1));
    raise exception 'Expected insufficient monthly headroom for a full slot to fail';
  exception when sqlstate '54000' then null; end;
  update private.pomodoist_upload_months set bytes=0 where user_id=actor;
  update private.pomodoist_upload_years set bytes=4980000001 where user_id=actor;
  begin
    perform public.pomodoist_files(jsonb_build_object('action','reserveUpload','taskId','quota-test',
      'uploadId',gen_random_uuid(),'name','small.txt','contentType','text/plain','bytes',1));
    raise exception 'Expected insufficient yearly headroom for a full slot to fail';
  exception when sqlstate '54000' then null; end;

  update storage.buckets set file_size_limit=null where id='pomodoist-shared';
  result:=public.pomodoist_files('{"action":"capabilities","taskId":"quota-test"}');
  assert result->>'canUpload'='false' and result->>'reason'='storage_unavailable',
    'An unbounded bucket must fail closed';
  update storage.buckets set file_size_limit=20000000 where id='pomodoist-shared';
  -- A free editor's shared uploads reserve the sponsoring owner's full slot.
  update public.user_entitlements set status='revoked' where user_id=actor;
  insert into auth.users(id,email,aud,role,created_at,updated_at)
    values(owner_id,owner_id::text||'@example.test','authenticated','authenticated',now(),now());
  insert into public.user_entitlements(user_id,app_id,entitlement_id,source,purchase_type,status)
    values(owner_id,'pomodoist','test:shared-upload-quota','app_store','lifetime','active');
  insert into private.pomodoist_scopes(id,owner_id,root_project_id) values(shared_scope,owner_id,'quota-project');
  insert into private.pomodoist_members(scope_id,user_id,role)
    values(shared_scope,owner_id,'administrator'),(shared_scope,actor,'member');
  insert into private.pomodoist_shared_entities(scope_id,entity_type,entity_id,server_revision,data)
    values(shared_scope,'task','quota-test',nextval('public.sync_revision_seq'),'{"content":"Shared quota test"}');
  insert into private.pomodoist_upload_months(user_id,month,bytes)
    values(owner_id,date_trunc('month',now() at time zone 'UTC')::date,980000000);
  upload_id:=gen_random_uuid();
  perform public.pomodoist_files(jsonb_build_object('action','reserveUpload','scopeId',shared_scope,'taskId','quota-test',
    'uploadId',upload_id,'name','small.txt','contentType','text/plain','bytes',1));
  assert (select quota_user_id=owner_id from private.pomodoist_uploads where id=upload_id);
  result:=public.pomodoist_files(jsonb_build_object('action','capabilities','scopeId',shared_scope,'taskId','quota-test'));
  assert result->>'reservedBytes'='20000000' and result->>'canUpload'='false';
  begin
    perform public.pomodoist_files(jsonb_build_object('action','reserveUpload','scopeId',shared_scope,'taskId','quota-test',
      'uploadId',gen_random_uuid(),'name','small.txt','contentType','text/plain','bytes',1));
    raise exception 'Expected the sponsoring owner quota to block a second slot';
  exception when sqlstate '54000' then null; end;
  assert not has_function_privilege('anon','public.pomodoist_files(jsonb)','execute');
end $$;
select pass('upload quota hold regression checks passed');
select * from finish();
rollback;
