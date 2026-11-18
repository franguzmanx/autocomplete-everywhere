begin;
select plan(10);

select hasnt_column(
  'public',
  'suggestion_events',
  'language_code',
  'suggestion events no longer carry a client language code'
);

select has_column(
  'public',
  'suggestion_events',
  'request_to_final_ms',
  'suggestion events record request-to-final latency'
);

select hasnt_column(
  'public',
  'suggestion_events',
  'content',
  'suggestion events still have no content column'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"outcome_user_a","role":"authenticated"}',
  true
);

select lives_ok(
  $$
    select public.record_suggestion_outcome(
      '30000000-0000-0000-0000-000000000101',
      'com.apple.Notes',
      'text_editor',
      'requested'
    )
  $$,
  'a first-time user records a requested outcome without a prior profile'
);

select is(
  (select count(*)::integer from public.users where id = 'outcome_user_a'),
  1,
  'recording an outcome creates the canonical user row once'
);

select lives_ok(
  $$
    select public.record_suggestion_outcome(
      '30000000-0000-0000-0000-000000000101',
      'com.apple.Notes',
      'text_editor',
      'shown',
      480,
      420,
      21,
      null,
      null,
      'zai/glm-5.3-flash'
    )
  $$,
  'the same request records a shown outcome with latency'
);

select lives_ok(
  $$
    select public.record_suggestion_outcome(
      '30000000-0000-0000-0000-000000000101',
      'com.apple.Notes',
      'text_editor',
      'shown',
      900
    )
  $$,
  'a repeated shown report is ignored rather than rejected'
);

select is(
  (
    select count(*)::integer
    from public.suggestion_events
    where request_id = '30000000-0000-0000-0000-000000000101'
  ),
  2,
  'one request keeps one row per outcome'
);

select throws_ok(
  $$
    select public.record_suggestion_outcome(
      '30000000-0000-0000-0000-000000000102',
      'com.apple.Notes',
      'window_title_or_content',
      'shown'
    )
  $$,
  '22023',
  null,
  'an unknown surface class is rejected'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"outcome_user_b","role":"authenticated"}',
  true
);

select is(
  (select count(*)::integer from public.suggestion_events),
  0,
  'another user cannot read the recorded outcomes'
);

reset role;
select * from finish();
rollback;
