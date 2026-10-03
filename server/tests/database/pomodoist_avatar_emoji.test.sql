begin;
\ir hosted-mode.inc

select plan(14);

select has_column('public', 'profiles', 'avatar_emoji', 'profiles has an emoji avatar');
select ok(has_column_privilege('authenticated', 'public.profiles', 'avatar_emoji', 'UPDATE'),
  'authenticated clients can edit emoji presentation');
select ok(not has_column_privilege('authenticated', 'public.profiles', 'pomodoist_is_pro', 'UPDATE'),
  'emoji editing does not grant privileged profile updates');

insert into auth.users (id, email, aud, role, created_at, updated_at) values
  ('a7a70000-0000-4000-8000-000000000001', 'avatar-a@example.test', 'authenticated', 'authenticated', now(), now()),
  ('a7a70000-0000-4000-8000-000000000002', 'avatar-b@example.test', 'authenticated', 'authenticated', now(), now());
insert into auth.sessions (id, user_id, created_at, updated_at) values
  ('a7a70000-0000-4000-8000-000000000011', 'a7a70000-0000-4000-8000-000000000001', now(), now());
update public.profiles set avatar_url = 'https://example.test/avatar.png'
  where id = 'a7a70000-0000-4000-8000-000000000001';

-- Hosted defaults grant anon table privileges; existing RLS still denies writes.
set local role anon;
with changed as (
  update public.profiles set avatar_emoji = '😀'
  where id = 'a7a70000-0000-4000-8000-000000000001' returning id
) select is((select count(*) from changed), 0::bigint,
  'anonymous clients cannot edit emoji presentation');
reset role;

set local role authenticated;
set local request.jwt.claims = '{"sub":"a7a70000-0000-4000-8000-000000000001","session_id":"a7a70000-0000-4000-8000-000000000011","role":"authenticated"}';

select is(public.get_account_overview() #> '{profile,avatarEmoji}', 'null'::jsonb,
  'existing profiles expose a null emoji avatar');
select lives_ok($$update public.profiles set avatar_emoji = '👨‍👩‍👧‍👦'
  where id = 'a7a70000-0000-4000-8000-000000000001'$$,
  'owners can save complete ZWJ emoji sequences');
select is(public.get_account_overview() #>> '{profile,avatarEmoji}', '👨‍👩‍👧‍👦',
  'account RPC returns the complete saved sequence');
select is(public.get_account_overview() #>> '{profile,avatarUrl}', 'https://example.test/avatar.png',
  'emoji updates preserve OAuth profile image URLs');

with changed as (
  update public.profiles set avatar_emoji = '😀'
  where id = 'a7a70000-0000-4000-8000-000000000002' returning id
) select is((select count(*) from changed), 0::bigint,
  'RLS prevents changing another account avatar');

select throws_ok($$update public.profiles set avatar_emoji = ''
  where id = 'a7a70000-0000-4000-8000-000000000001'$$,
  '23514', null, 'empty values cannot masquerade as a reset');
select throws_ok($$update public.profiles set avatar_emoji = repeat('😀', 33)
  where id = 'a7a70000-0000-4000-8000-000000000001'$$,
  '23514', null, 'oversized avatar payloads are rejected');
select lives_ok($$update public.profiles set avatar_emoji = null
  where id = 'a7a70000-0000-4000-8000-000000000001'$$,
  'owners can reset their avatar');
select is(public.get_account_overview() #> '{profile,avatarEmoji}', 'null'::jsonb,
  'the RPC exposes reset as null');

reset role;
delete from auth.sessions where id = 'a7a70000-0000-4000-8000-000000000011';
set local role authenticated;
with changed as (
  update public.profiles set avatar_emoji = '😀'
  where id = 'a7a70000-0000-4000-8000-000000000001' returning id
) select is((select count(*) from changed), 0::bigint,
  'revoked sessions cannot edit their own avatar');
reset role;
select * from finish();
rollback;
