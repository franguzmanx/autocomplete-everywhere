-- Content-free suggestion outcomes recorded by the desktop through the API.
--
-- The desktop correlates the helper's request, the API response, and the
-- helper's interaction report into one lifecycle per request:
--   requested -> generated | suppressed | failed | cancelled
--   generated -> shown -> accepted_full | accepted_partial | typed_through
--                         | dismissed | stale | failed
-- Rows carry identifiers, surface class, outcome, and timing. They never
-- carry field text, suggestion text, or clipboard contents.

alter type public.suggestion_outcome add value if not exists 'generated';
alter type public.suggestion_outcome add value if not exists 'cancelled';

-- The client no longer classifies language; the model infers it from the
-- request. The column was a leftover of that removed layer.
alter table public.suggestion_events drop column language_code;

alter table public.suggestion_events
  add column request_to_final_ms integer check (request_to_final_ms >= 0);

comment on column public.suggestion_events.pause_to_first_visible_ms is
  'Desktop-measured milliseconds from the helper request timestamp to the helper shown report. Excludes the native quiet interval that precedes the request.';
comment on column public.suggestion_events.request_to_final_ms is
  'Desktop-measured milliseconds from the helper request timestamp to the final API response (text or silence).';
comment on column public.suggestion_events.app_category is
  'Host application bundle identifier reported by the helper. Application identity only; never window titles or content.';

create or replace function public.record_suggestion_outcome(
  target_request_id uuid,
  target_app_category text,
  target_surface_kind text,
  target_outcome public.suggestion_outcome,
  target_pause_to_first_visible_ms integer default null,
  target_request_to_final_ms integer default null,
  target_suggestion_char_count integer default null,
  target_accepted_char_count integer default null,
  target_error_class text default null,
  target_model_id text default null
)
returns boolean
language plpgsql
security invoker
set search_path = ''
as $$
declare
  current_user_id text := (select private.current_user_id());
begin
  if current_user_id is null then
    raise exception 'authenticated user required' using errcode = '42501';
  end if;
  if target_app_category is null
    or length(target_app_category) = 0
    or length(target_app_category) > 256
  then
    raise exception 'invalid app category' using errcode = '22023';
  end if;
  if target_surface_kind not in ('text_editor', 'web_textarea') then
    raise exception 'invalid surface kind' using errcode = '22023';
  end if;
  if length(coalesce(target_error_class, '')) > 100
    or length(coalesce(target_model_id, '')) > 200
  then
    raise exception 'invalid outcome detail' using errcode = '22001';
  end if;

  insert into public.users (id)
  values (current_user_id)
  on conflict (id) do nothing;

  insert into public.suggestion_events (
    user_id,
    request_id,
    app_category,
    surface_kind,
    outcome,
    pause_to_first_visible_ms,
    request_to_final_ms,
    suggestion_char_count,
    accepted_char_count,
    error_class,
    model_id
  ) values (
    current_user_id,
    target_request_id,
    target_app_category,
    target_surface_kind,
    target_outcome,
    target_pause_to_first_visible_ms,
    target_request_to_final_ms,
    target_suggestion_char_count,
    target_accepted_char_count,
    target_error_class,
    target_model_id
  )
  on conflict (user_id, request_id, outcome) do nothing;

  return true;
end;
$$;

revoke all on function public.record_suggestion_outcome(
  uuid, text, text, public.suggestion_outcome, integer, integer, integer, integer, text, text
) from public, anon;
grant execute on function public.record_suggestion_outcome(
  uuid, text, text, public.suggestion_outcome, integer, integer, integer, integer, text, text
) to authenticated;
