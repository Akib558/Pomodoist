begin;
select no_plan();

insert into auth.users(id,email,aud,role,created_at,updated_at) values
  ('bc000000-0000-4000-8000-000000000001','session-alice@example.test','authenticated','authenticated',now(),now()),
  ('bc000000-0000-4000-8000-000000000002','session-bob@example.test','authenticated','authenticated',now(),now());
insert into auth.sessions(id,user_id,created_at,updated_at,not_after) values
  ('bc000000-0000-4000-8000-000000000011','bc000000-0000-4000-8000-000000000001',now(),now(),null),
  ('bc000000-0000-4000-8000-000000000012','bc000000-0000-4000-8000-000000000001',now(),now(),null),
  ('bc000000-0000-4000-8000-000000000021','bc000000-0000-4000-8000-000000000002',now(),now(),null);

set local role authenticated;
set local request.jwt.claims='{"sub":"bc000000-0000-4000-8000-000000000001","session_id":"bc000000-0000-4000-8000-000000000012","role":"authenticated"}';
select lives_ok('select public.pomodoist_check_session()', 'active session passes the Data API guard');
select is((select count(*) from public.profiles),1::bigint,'active session reads its own profile');
update public.profiles set display_name='Active session' where id=auth.uid();
select is((select display_name from public.profiles where id=auth.uid()),'Active session','active session writes its own profile');
select lives_ok($$insert into public.user_app_installs(user_id,app_id,device_id) values(auth.uid(),'pomodoist','active-session')$$,'active session can register a device');

reset role;
delete from auth.sessions where id='bc000000-0000-4000-8000-000000000012';
set local role authenticated;
select throws_ok('select public.pomodoist_check_session()','PT401','Session is no longer active','revoked session fails the Data API guard');
select is((select count(*) from public.profiles),0::bigint,'RLS hides profile from revoked session without a pre-request hook');
with changed as (update public.profiles set display_name='Revoked write' returning id)
select is(count(*),0::bigint,'revoked session cannot update profile') from changed;
select throws_ok($$insert into public.user_app_installs(user_id,app_id,device_id) values(auth.uid(),'pomodoist','revoked-session')$$,
  '42501',null,'revoked session cannot register a device');

set local request.jwt.claims='{"sub":"bc000000-0000-4000-8000-000000000001","session_id":"bc000000-0000-4000-8000-000000000011","role":"authenticated"}';
select lives_ok('select public.pomodoist_check_session()','other session of the account remains active');
select is((select display_name from public.profiles where id=auth.uid()),'Active session','revoked write did not change profile');
reset role;
update auth.sessions set not_after=statement_timestamp()-interval '1 second' where id='bc000000-0000-4000-8000-000000000011';
set local role authenticated;
select throws_ok('select public.pomodoist_check_session()','PT401','Session is no longer active','expired session cannot use an unexpired JWT');

set local request.jwt.claims='{"sub":"bc000000-0000-4000-8000-000000000001","session_id":"bc000000-0000-4000-8000-000000000021","role":"authenticated"}';
select throws_ok('select public.pomodoist_check_session()','PT401','Session is no longer active','another users active session cannot authorize the subject');
set local request.jwt.claims='{"sub":"bc000000-0000-4000-8000-000000000001","role":"authenticated"}';
select throws_ok('select public.pomodoist_check_session()','PT401','Session is no longer active','missing session identifier fails closed');
set local request.jwt.claims='{"sub":"bc000000-0000-4000-8000-000000000001","session_id":"invalid","role":"authenticated"}';
select throws_ok('select public.pomodoist_check_session()','PT401','Session is no longer active','malformed session identifier fails closed');

set local role anon;
set local request.jwt.claims='{"role":"anon"}';
select lives_ok('select public.pomodoist_check_session()','anonymous requests retain their existing ACL and RLS checks');
reset role;
select ok(not has_function_privilege('anon','private.pomodoist_session_is_active()','EXECUTE'),'anonymous users cannot query Auth sessions');
set local role service_role;
set local request.jwt.claims='{"role":"service_role"}';
select lives_ok('select public.pomodoist_check_session()','server requests do not require a user session');
reset role;
select ok(not has_table_privilege('authenticated','auth.sessions','SELECT'),'clients do not receive direct access to Auth sessions');
select * from finish();
rollback;
