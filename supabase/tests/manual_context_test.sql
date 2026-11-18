begin;
select plan(8);

insert into public.users (id) values ('profile_user_a'), ('profile_user_b');

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"profile_user_a","role":"authenticated"}',
  true
);

select lives_ok(
  $$ select public.replace_manual_context('Writes concise replies', 'Builds Autocomplete Everywhere') $$,
  'user A can replace their manual context atomically'
);

select is(
  (select personal_context from public.read_manual_context()),
  'Writes concise replies',
  'user A reads their personal profile'
);

select is(
  (select company_context from public.read_manual_context()),
  'Builds Autocomplete Everywhere',
  'user A reads their company profile'
);

select is(
  (
    select count(*)::integer
    from public.knowledge_items
    where metadata->>'profile_scope' in ('personal', 'company')
  ),
  2,
  'the profile creates two separately scoped canonical items'
);

select lives_ok(
  $$ select public.replace_manual_context('Updated personal profile', '') $$,
  'replacing context supports clearing one scope'
);

select is(
  (select personal_context from public.read_manual_context()),
  'Updated personal profile',
  'replacement returns the current personal profile'
);

select is(
  (select company_context from public.read_manual_context()),
  '',
  'cleared company context does not survive replacement'
);

select is(
  (
    select count(*)::integer
    from public.knowledge_items
    where content = 'Builds Autocomplete Everywhere'
  ),
  0,
  'old profile content is not visible after replacement'
);

reset role;
select * from finish();
rollback;
