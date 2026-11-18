create policy users_insert_self on public.users
for insert to authenticated
with check (id = (select private.current_user_id()));

grant insert on public.users to authenticated;

create or replace function public.replace_manual_context(
  personal_context text,
  company_context text
)
returns boolean
language plpgsql
security invoker
set search_path = ''
as $$
declare
  current_user_id text := (select private.current_user_id());
  target_space_id uuid;
  target_source_id uuid;
  bounded_personal text := trim(coalesce(personal_context, ''));
  bounded_company text := trim(coalesce(company_context, ''));
begin
  if current_user_id is null then
    raise exception 'authenticated user required' using errcode = '42501';
  end if;
  if length(bounded_personal) > 20000 or length(bounded_company) > 20000 then
    raise exception 'manual context exceeds limit' using errcode = '22001';
  end if;
  if bounded_personal = '' and bounded_company = '' then
    raise exception 'at least one context scope is required' using errcode = '22023';
  end if;

  insert into public.users (id)
  values (current_user_id)
  on conflict (id) do nothing;

  insert into public.knowledge_spaces (kind, name, owner_user_id)
  values ('personal', 'Personal context', current_user_id)
  on conflict (owner_user_id) where kind = 'personal'
  do update set name = excluded.name
  returning id into target_space_id;

  insert into public.knowledge_sources (
    space_id,
    kind,
    external_id,
    title,
    created_by_user_id
  ) values (
    target_space_id,
    'manual',
    'manual-profile',
    'Manual profile',
    current_user_id
  )
  on conflict (space_id, kind, external_id)
  do update set title = excluded.title
  returning id into target_source_id;

  delete from public.knowledge_items
  where source_id = target_source_id;

  if bounded_personal <> '' then
    insert into public.knowledge_items (
      space_id,
      source_id,
      kind,
      title,
      content,
      content_hash,
      metadata
    ) values (
      target_space_id,
      target_source_id,
      'preference',
      'Personal profile',
      bounded_personal,
      encode(extensions.digest('personal:' || bounded_personal, 'sha256'), 'hex'),
      jsonb_build_object('profile_scope', 'personal')
    );
  end if;

  if bounded_company <> '' then
    insert into public.knowledge_items (
      space_id,
      source_id,
      kind,
      title,
      content,
      content_hash,
      metadata
    ) values (
      target_space_id,
      target_source_id,
      'policy',
      'Company profile',
      bounded_company,
      encode(extensions.digest('company:' || bounded_company, 'sha256'), 'hex'),
      jsonb_build_object('profile_scope', 'company')
    );
  end if;

  return true;
end;
$$;

create or replace function public.read_manual_context()
returns table (
  personal_context text,
  company_context text
)
language sql
stable
security invoker
set search_path = ''
as $$
  select
    coalesce(
      max(item.content) filter (where item.metadata->>'profile_scope' = 'personal'),
      ''
    ) as personal_context,
    coalesce(
      max(item.content) filter (where item.metadata->>'profile_scope' = 'company'),
      ''
    ) as company_context
  from public.knowledge_spaces space
  left join public.knowledge_sources source
    on source.space_id = space.id
    and source.kind = 'manual'
    and source.external_id = 'manual-profile'
  left join public.knowledge_items item
    on item.space_id = space.id
    and item.source_id = source.id
    and item.status = 'active'
    and item.is_current
  where space.kind = 'personal'
    and space.owner_user_id = (select private.current_user_id());
$$;

revoke all on function public.replace_manual_context(text, text) from public, anon;
revoke all on function public.read_manual_context() from public, anon;
grant execute on function public.replace_manual_context(text, text) to authenticated;
grant execute on function public.read_manual_context() to authenticated;
