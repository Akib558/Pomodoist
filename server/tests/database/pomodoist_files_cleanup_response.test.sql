-- Run against a migrated database. All fixtures are temporary; no HTTP calls.
begin;
create temp table cleanup_request (like private.pomodoist_files_cleanup_request including all);
create temp table cleanup_response (like net._http_response including all);
do $$
declare source text;
begin
  source := pg_get_functiondef('private.check_pomodoist_files_cleanup()'::regprocedure);
  source := replace(source,'private.check_pomodoist_files_cleanup','pg_temp.check_cleanup');
  source := replace(source,'private.pomodoist_files_cleanup_request','pg_temp.cleanup_request');
  source := replace(source,'net._http_response','pg_temp.cleanup_response');
  execute source;
end $$;
create function pg_temp.cleanup_fails() returns boolean language plpgsql as $$
begin
  perform pg_temp.check_cleanup();
  return false;
exception when raise_exception or invalid_text_representation then return true;
end $$;
do $$
begin
  perform pg_temp.check_cleanup(); -- Idle worker is healthy.
  insert into pg_temp.cleanup_request(singleton,request_id) values(true,-1);
  perform pg_temp.check_cleanup(); -- Give asynchronous dispatch time to finish.
  assert (select not checked from pg_temp.cleanup_request);
  update pg_temp.cleanup_request set requested_at=now()-interval '3 minutes';
  assert pg_temp.cleanup_fails(), 'A missing response must fail after the deadline';
  insert into pg_temp.cleanup_response(id,status_code,content) values(-1,401,'{"error":"Authentication required"}');
  assert pg_temp.cleanup_fails(), 'HTTP 401 must fail';
  update pg_temp.cleanup_response set status_code=503;
  assert pg_temp.cleanup_fails(), 'HTTP 503 must fail';
  update pg_temp.cleanup_response set status_code=200,content='{"ok":false}';
  assert pg_temp.cleanup_fails(), 'HTTP 200 without completion must fail';
  update pg_temp.cleanup_response set content='invalid json';
  assert pg_temp.cleanup_fails(), 'Malformed completion must fail';
  update pg_temp.cleanup_response set content='{"ok":true}',timed_out=true;
  assert pg_temp.cleanup_fails(), 'A timeout must fail';
  update pg_temp.cleanup_response set timed_out=false,error_msg='Network failure';
  assert pg_temp.cleanup_fails(), 'A transport error must fail';
  update pg_temp.cleanup_response set error_msg=null;
  perform pg_temp.check_cleanup();
  assert (select checked from pg_temp.cleanup_request), 'Successful retry must be acknowledged';
  delete from pg_temp.cleanup_response;
  perform pg_temp.check_cleanup(); -- Completed requests stay healthy after pg_net TTL.
  assert not has_function_privilege('authenticated','private.check_pomodoist_files_cleanup()','execute');
  assert not has_function_privilege('anon','private.invoke_pomodoist_files_cleanup()','execute');
  assert not has_table_privilege('authenticated','private.pomodoist_files_cleanup_request','select');
end $$;
select 'cleanup response regression checks passed' as result;
rollback;
