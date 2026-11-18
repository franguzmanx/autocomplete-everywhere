begin;
select plan(14);

insert into public.users (id, primary_email, display_name) values
  ('user_a', 'a@example.test', 'A'),
  ('user_b', 'b@example.test', 'B');

insert into public.organizations (id, name) values
  ('org_a', 'Organization A');

insert into public.organization_memberships (organization_id, user_id, role) values
  ('org_a', 'user_a', 'org:member');

insert into public.knowledge_spaces (id, kind, name, owner_user_id) values
  ('10000000-0000-0000-0000-000000000001', 'personal', 'A personal', 'user_a'),
  ('10000000-0000-0000-0000-000000000002', 'personal', 'B personal', 'user_b');

insert into public.knowledge_spaces (id, kind, name, organization_id) values
  ('10000000-0000-0000-0000-000000000003', 'organization', 'A company', 'org_a');

insert into public.knowledge_items (
  id,
  space_id,
  kind,
  content,
  content_hash,
  language_code
) values
  (
    '20000000-0000-0000-0000-000000000001',
    '10000000-0000-0000-0000-000000000001',
    'preference',
    'A personal fact',
    'hash-a',
    'en'
  ),
  (
    '20000000-0000-0000-0000-000000000002',
    '10000000-0000-0000-0000-000000000002',
    'preference',
    'B personal fact',
    'hash-b',
    'en'
  ),
  (
    '20000000-0000-0000-0000-000000000003',
    '10000000-0000-0000-0000-000000000003',
    'policy',
    'Organization A policy',
    'hash-org-a',
    'en'
  );

insert into public.device_installations (
  id,
  user_id,
  installation_id,
  platform
) values
  (
    '40000000-0000-0000-0000-000000000001',
    'user_a',
    'device-a',
    'macos'
  ),
  (
    '40000000-0000-0000-0000-000000000002',
    'user_b',
    'device-b',
    'macos'
  );

select ok(
  (select relrowsecurity from pg_class where oid = 'public.knowledge_items'::regclass),
  'knowledge_items has RLS enabled'
);

select ok(
  not has_table_privilege('anon', 'public.knowledge_items', 'select'),
  'anon has no knowledge_items read grant'
);

select ok(
  has_table_privilege('authenticated', 'public.knowledge_items', 'select'),
  'authenticated has the knowledge_items read grant'
);

select hasnt_column(
  'public',
  'suggestion_events',
  'content',
  'suggestion telemetry has no content column'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"user_a","role":"authenticated","org_id":"org_a"}',
  true
);

select is(
  (select count(*)::integer from public.knowledge_spaces),
  2,
  'user A sees personal A and organization A spaces'
);

select is(
  (
    select count(*)::integer
    from public.knowledge_items
    where content = 'A personal fact'
  ),
  1,
  'user A sees their personal knowledge'
);

select is(
  (
    select count(*)::integer
    from public.knowledge_items
    where content = 'B personal fact'
  ),
  0,
  'user A cannot see user B personal knowledge'
);

select is(
  (
    select count(*)::integer
    from public.knowledge_items
    where content = 'Organization A policy'
  ),
  1,
  'organization member sees organization knowledge'
);

select lives_ok(
  $$
    insert into public.knowledge_items (
      space_id,
      kind,
      content,
      content_hash,
      language_code
    ) values (
      '10000000-0000-0000-0000-000000000001',
      'instruction',
      'Write concise replies',
      'hash-a-write',
      'en'
    )
  $$,
  'user A can write to their personal space'
);

select throws_ok(
  $$
    insert into public.knowledge_items (
      space_id,
      kind,
      content,
      content_hash,
      language_code
    ) values (
      '10000000-0000-0000-0000-000000000002',
      'instruction',
      'Attempted cross-user write',
      'hash-b-write',
      'en'
    )
  $$,
  '42501',
  null,
  'user A cannot write to user B personal space'
);

select lives_ok(
  $$
    insert into public.suggestion_events (
      user_id,
      request_id,
      app_category,
      outcome
    ) values (
      'user_a',
      '30000000-0000-0000-0000-000000000001',
      'notes',
      'shown'
    )
  $$,
  'user A can record their own content-free event'
);

select lives_ok(
  $$
    insert into public.suggestion_events (
      user_id,
      device_id,
      organization_id,
      request_id,
      app_category,
      outcome
    ) values (
      'user_a',
      '40000000-0000-0000-0000-000000000001',
      'org_a',
      '30000000-0000-0000-0000-000000000003',
      'slack',
      'shown'
    )
  $$,
  'user A can record an organization event for their own device'
);

select throws_ok(
  $$
    insert into public.suggestion_events (
      user_id,
      device_id,
      request_id,
      app_category,
      outcome
    ) values (
      'user_a',
      '40000000-0000-0000-0000-000000000002',
      '30000000-0000-0000-0000-000000000004',
      'notes',
      'shown'
    )
  $$,
  '23503',
  null,
  'user A cannot attach user B device to an event'
);

select throws_ok(
  $$
    insert into public.suggestion_events (
      user_id,
      request_id,
      app_category,
      outcome
    ) values (
      'user_b',
      '30000000-0000-0000-0000-000000000002',
      'notes',
      'shown'
    )
  $$,
  '42501',
  null,
  'user A cannot record an event for user B'
);

reset role;

select * from finish();
rollback;
