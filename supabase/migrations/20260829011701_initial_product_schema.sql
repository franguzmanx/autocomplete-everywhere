create extension if not exists vector with schema extensions;
create extension if not exists pg_trgm with schema extensions;
create extension if not exists pgcrypto with schema extensions;

create schema if not exists private;
revoke all on schema private from public, anon;
grant usage on schema private to authenticated;

create type public.knowledge_space_kind as enum ('personal', 'organization');
create type public.knowledge_source_kind as enum (
  'manual',
  'app_context',
  'slack',
  'email',
  'document',
  'meeting',
  'crm',
  'figma',
  'repository',
  'web'
);
create type public.knowledge_item_kind as enum (
  'document',
  'fact',
  'preference',
  'instruction',
  'episode',
  'policy',
  'proof'
);
create type public.knowledge_item_status as enum ('active', 'archived', 'deleted');
create type public.knowledge_relation_kind as enum ('updates', 'extends', 'derives', 'evidence');
create type public.device_platform as enum ('macos', 'windows');
create type public.suggestion_outcome as enum (
  'requested',
  'suppressed',
  'shown',
  'accepted_full',
  'accepted_partial',
  'dismissed',
  'typed_through',
  'stale',
  'failed'
);

create or replace function private.current_user_id()
returns text
language sql
stable
security invoker
set search_path = ''
as $$
  select nullif((select auth.jwt()->>'sub'), '');
$$;

grant execute on function private.current_user_id() to authenticated;

create or replace function private.set_updated_at()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  new.updated_at = timezone('utc', now());
  return new;
end;
$$;

create table public.users (
  id text primary key,
  primary_email text,
  display_name text,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table public.organizations (
  id text primary key,
  name text not null,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table public.organization_memberships (
  organization_id text not null references public.organizations(id) on delete cascade,
  user_id text not null references public.users(id) on delete cascade,
  role text not null check (role in ('org:member', 'org:admin', 'org:owner')),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  primary key (organization_id, user_id)
);

create table public.knowledge_spaces (
  id uuid primary key default gen_random_uuid(),
  kind public.knowledge_space_kind not null,
  name text not null,
  owner_user_id text references public.users(id) on delete cascade,
  organization_id text references public.organizations(id) on delete cascade,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint knowledge_spaces_owner_matches_kind check (
    (kind = 'personal' and owner_user_id is not null and organization_id is null)
    or
    (kind = 'organization' and owner_user_id is null and organization_id is not null)
  )
);

create unique index knowledge_spaces_one_personal_per_user
  on public.knowledge_spaces(owner_user_id)
  where kind = 'personal';

create index knowledge_spaces_organization_idx
  on public.knowledge_spaces(organization_id)
  where kind = 'organization';

create table public.knowledge_sources (
  id uuid primary key default gen_random_uuid(),
  space_id uuid not null references public.knowledge_spaces(id) on delete cascade,
  kind public.knowledge_source_kind not null,
  external_id text,
  title text,
  storage_path text,
  content_hash text,
  source_updated_at timestamptz,
  last_synced_at timestamptz,
  created_by_user_id text references public.users(id) on delete set null,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (id, space_id),
  unique (space_id, kind, external_id)
);

create index knowledge_sources_space_idx on public.knowledge_sources(space_id);

create table public.knowledge_items (
  id uuid primary key default gen_random_uuid(),
  space_id uuid not null references public.knowledge_spaces(id) on delete cascade,
  source_id uuid references public.knowledge_sources(id) on delete cascade,
  kind public.knowledge_item_kind not null,
  status public.knowledge_item_status not null default 'active',
  title text,
  content text not null,
  content_hash text not null,
  language_code text not null default 'und',
  confidence numeric(4, 3) check (confidence between 0 and 1),
  valid_from timestamptz,
  valid_until timestamptz,
  is_current boolean not null default true,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  search_vector tsvector generated always as (
    to_tsvector('simple', coalesce(title, '') || ' ' || content)
  ) stored,
  foreign key (source_id, space_id)
    references public.knowledge_sources(id, space_id) on delete cascade,
  unique (id, space_id),
  unique (space_id, content_hash)
);

create index knowledge_items_space_current_idx
  on public.knowledge_items(space_id, updated_at desc)
  where status = 'active' and is_current;

create index knowledge_items_source_idx on public.knowledge_items(source_id);
create index knowledge_items_search_vector_idx on public.knowledge_items using gin(search_vector);
create index knowledge_items_trigram_idx
  on public.knowledge_items
  using gin ((lower(coalesce(title, '') || ' ' || content)) extensions.gin_trgm_ops);

create table public.knowledge_relations (
  id uuid primary key default gen_random_uuid(),
  space_id uuid not null references public.knowledge_spaces(id) on delete cascade,
  from_item_id uuid not null,
  to_item_id uuid not null,
  kind public.knowledge_relation_kind not null,
  created_at timestamptz not null default timezone('utc', now()),
  foreign key (from_item_id, space_id)
    references public.knowledge_items(id, space_id) on delete cascade,
  foreign key (to_item_id, space_id)
    references public.knowledge_items(id, space_id) on delete cascade,
  unique (from_item_id, to_item_id, kind),
  check (from_item_id <> to_item_id)
);

create index knowledge_relations_space_idx on public.knowledge_relations(space_id);
create index knowledge_relations_to_item_idx on public.knowledge_relations(to_item_id);

create table public.knowledge_embeddings (
  item_id uuid not null,
  space_id uuid not null references public.knowledge_spaces(id) on delete cascade,
  model_id text not null,
  dimensions integer not null default 1024 check (dimensions = 1024),
  embedding extensions.vector(1024) not null,
  created_at timestamptz not null default timezone('utc', now()),
  primary key (item_id, model_id),
  foreign key (item_id, space_id)
    references public.knowledge_items(id, space_id) on delete cascade
);

create index knowledge_embeddings_space_model_idx
  on public.knowledge_embeddings(space_id, model_id);
create index knowledge_embeddings_hnsw_idx
  on public.knowledge_embeddings
  using hnsw (embedding extensions.vector_cosine_ops);

create table public.device_installations (
  id uuid primary key default gen_random_uuid(),
  user_id text not null references public.users(id) on delete cascade,
  installation_id text not null,
  platform public.device_platform not null,
  app_version text,
  helper_version text,
  last_seen_at timestamptz,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (id, user_id),
  unique (user_id, installation_id)
);

create table public.user_preferences (
  user_id text primary key references public.users(id) on delete cascade,
  preferred_language_codes text[] not null default '{}'::text[],
  autocomplete_enabled boolean not null default true,
  personal_context_enabled boolean not null default true,
  company_context_enabled boolean not null default true,
  pause_ms integer not null default 450 check (pause_ms between 150 and 3000),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table public.experiment_assignments (
  user_id text not null references public.users(id) on delete cascade,
  experiment_key text not null,
  variant_key text not null,
  assigned_at timestamptz not null default timezone('utc', now()),
  primary key (user_id, experiment_key)
);

create table public.suggestion_events (
  id uuid primary key default gen_random_uuid(),
  user_id text not null references public.users(id) on delete cascade,
  device_id uuid,
  organization_id text references public.organizations(id) on delete set null,
  request_id uuid not null,
  experiment_key text,
  variant_key text,
  app_category text not null,
  surface_kind text,
  language_code text not null default 'und',
  model_id text,
  outcome public.suggestion_outcome not null,
  pause_to_first_visible_ms integer check (pause_to_first_visible_ms >= 0),
  provider_latency_ms integer check (provider_latency_ms >= 0),
  suggestion_char_count integer check (suggestion_char_count >= 0),
  accepted_char_count integer check (accepted_char_count >= 0),
  error_class text,
  created_at timestamptz not null default timezone('utc', now()),
  foreign key (device_id, user_id)
    references public.device_installations(id, user_id) on delete set null (device_id),
  unique (user_id, request_id, outcome)
);

create index suggestion_events_user_created_idx
  on public.suggestion_events(user_id, created_at desc);
create index suggestion_events_experiment_idx
  on public.suggestion_events(experiment_key, variant_key, created_at desc);

create trigger users_set_updated_at
before update on public.users
for each row execute function private.set_updated_at();

create trigger organizations_set_updated_at
before update on public.organizations
for each row execute function private.set_updated_at();

create trigger organization_memberships_set_updated_at
before update on public.organization_memberships
for each row execute function private.set_updated_at();

create trigger knowledge_spaces_set_updated_at
before update on public.knowledge_spaces
for each row execute function private.set_updated_at();

create trigger knowledge_sources_set_updated_at
before update on public.knowledge_sources
for each row execute function private.set_updated_at();

create trigger knowledge_items_set_updated_at
before update on public.knowledge_items
for each row execute function private.set_updated_at();

create trigger device_installations_set_updated_at
before update on public.device_installations
for each row execute function private.set_updated_at();

create trigger user_preferences_set_updated_at
before update on public.user_preferences
for each row execute function private.set_updated_at();

alter table public.users enable row level security;
alter table public.organizations enable row level security;
alter table public.organization_memberships enable row level security;
alter table public.knowledge_spaces enable row level security;
alter table public.knowledge_sources enable row level security;
alter table public.knowledge_items enable row level security;
alter table public.knowledge_relations enable row level security;
alter table public.knowledge_embeddings enable row level security;
alter table public.device_installations enable row level security;
alter table public.user_preferences enable row level security;
alter table public.experiment_assignments enable row level security;
alter table public.suggestion_events enable row level security;

create policy users_select_self on public.users
for select to authenticated
using (id = private.current_user_id());

create policy users_update_self on public.users
for update to authenticated
using (id = private.current_user_id())
with check (id = private.current_user_id());

create policy memberships_select_self on public.organization_memberships
for select to authenticated
using (user_id = private.current_user_id());

create policy organizations_select_member on public.organizations
for select to authenticated
using (
  exists (
    select 1
    from public.organization_memberships membership
    where membership.organization_id = organizations.id
      and membership.user_id = private.current_user_id()
  )
);

create policy spaces_select_allowed on public.knowledge_spaces
for select to authenticated
using (
  owner_user_id = private.current_user_id()
  or exists (
    select 1
    from public.organization_memberships membership
    where membership.organization_id = knowledge_spaces.organization_id
      and membership.user_id = private.current_user_id()
  )
);

create policy spaces_insert_personal on public.knowledge_spaces
for insert to authenticated
with check (
  kind = 'personal'
  and owner_user_id = private.current_user_id()
  and organization_id is null
);

create policy spaces_update_allowed on public.knowledge_spaces
for update to authenticated
using (
  owner_user_id = private.current_user_id()
  or exists (
    select 1
    from public.organization_memberships membership
    where membership.organization_id = knowledge_spaces.organization_id
      and membership.user_id = private.current_user_id()
      and membership.role in ('org:admin', 'org:owner')
  )
)
with check (
  owner_user_id = private.current_user_id()
  or exists (
    select 1
    from public.organization_memberships membership
    where membership.organization_id = knowledge_spaces.organization_id
      and membership.user_id = private.current_user_id()
      and membership.role in ('org:admin', 'org:owner')
  )
);

create policy spaces_delete_allowed on public.knowledge_spaces
for delete to authenticated
using (
  owner_user_id = private.current_user_id()
  or exists (
    select 1
    from public.organization_memberships membership
    where membership.organization_id = knowledge_spaces.organization_id
      and membership.user_id = private.current_user_id()
      and membership.role = 'org:owner'
  )
);

create or replace function private.can_read_space(target_space_id uuid)
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select exists (
    select 1 from public.knowledge_spaces space where space.id = target_space_id
  );
$$;

create or replace function private.can_write_space(target_space_id uuid)
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select exists (
    select 1
    from public.knowledge_spaces space
    where space.id = target_space_id
      and (
        space.owner_user_id = private.current_user_id()
        or exists (
          select 1
          from public.organization_memberships membership
          where membership.organization_id = space.organization_id
            and membership.user_id = private.current_user_id()
            and membership.role in ('org:admin', 'org:owner')
        )
      )
  );
$$;

grant execute on function private.can_read_space(uuid) to authenticated;
grant execute on function private.can_write_space(uuid) to authenticated;

create policy sources_select_allowed on public.knowledge_sources
for select to authenticated
using (private.can_read_space(space_id));

create policy sources_insert_allowed on public.knowledge_sources
for insert to authenticated
with check (private.can_write_space(space_id));

create policy sources_update_allowed on public.knowledge_sources
for update to authenticated
using (private.can_write_space(space_id))
with check (private.can_write_space(space_id));

create policy sources_delete_allowed on public.knowledge_sources
for delete to authenticated
using (private.can_write_space(space_id));

create policy items_select_allowed on public.knowledge_items
for select to authenticated
using (private.can_read_space(space_id));

create policy items_insert_allowed on public.knowledge_items
for insert to authenticated
with check (private.can_write_space(space_id));

create policy items_update_allowed on public.knowledge_items
for update to authenticated
using (private.can_write_space(space_id))
with check (private.can_write_space(space_id));

create policy items_delete_allowed on public.knowledge_items
for delete to authenticated
using (private.can_write_space(space_id));

create policy relations_select_allowed on public.knowledge_relations
for select to authenticated
using (private.can_read_space(space_id));

create policy relations_insert_allowed on public.knowledge_relations
for insert to authenticated
with check (private.can_write_space(space_id));

create policy relations_delete_allowed on public.knowledge_relations
for delete to authenticated
using (private.can_write_space(space_id));

create policy embeddings_select_allowed on public.knowledge_embeddings
for select to authenticated
using (private.can_read_space(space_id));

create policy devices_manage_self on public.device_installations
for all to authenticated
using (user_id = private.current_user_id())
with check (user_id = private.current_user_id());

create policy preferences_manage_self on public.user_preferences
for all to authenticated
using (user_id = private.current_user_id())
with check (user_id = private.current_user_id());

create policy experiments_select_self on public.experiment_assignments
for select to authenticated
using (user_id = private.current_user_id());

create policy suggestion_events_select_self on public.suggestion_events
for select to authenticated
using (user_id = private.current_user_id());

create policy suggestion_events_insert_self on public.suggestion_events
for insert to authenticated
with check (
  user_id = private.current_user_id()
  and (
    organization_id is null
    or exists (
      select 1
      from public.organization_memberships membership
      where membership.organization_id = suggestion_events.organization_id
        and membership.user_id = private.current_user_id()
    )
  )
);

revoke all on all tables in schema public from anon, authenticated;

grant select, update on public.users to authenticated;
grant select on public.organizations to authenticated;
grant select on public.organization_memberships to authenticated;
grant select, insert, update, delete on public.knowledge_spaces to authenticated;
grant select, insert, update, delete on public.knowledge_sources to authenticated;
grant select, insert, update, delete on public.knowledge_items to authenticated;
grant select, insert, delete on public.knowledge_relations to authenticated;
grant select on public.knowledge_embeddings to authenticated;
grant select, insert, update, delete on public.device_installations to authenticated;
grant select, insert, update, delete on public.user_preferences to authenticated;
grant select on public.experiment_assignments to authenticated;
grant select, insert on public.suggestion_events to authenticated;

create or replace function public.search_knowledge(
  query_text text,
  query_embedding extensions.vector(1024),
  query_model_id text,
  target_space_ids uuid[],
  match_count integer default 8
)
returns table (
  item_id uuid,
  space_id uuid,
  title text,
  content text,
  kind public.knowledge_item_kind,
  language_code text,
  score double precision
)
language sql
stable
security invoker
set search_path = ''
as $$
  with full_text as (
    select
      item.id,
      row_number() over (
        order by ts_rank_cd(item.search_vector, websearch_to_tsquery('simple', query_text)) desc
      ) as rank
    from public.knowledge_items item
    where item.space_id = any(target_space_ids)
      and item.status = 'active'
      and item.is_current
      and item.search_vector @@ websearch_to_tsquery('simple', query_text)
    order by rank
    limit least(greatest(match_count, 1) * 4, 40)
  ),
  semantic as (
    select
      item.id,
      row_number() over (
        order by embedding.embedding OPERATOR(extensions.<=>) query_embedding
      ) as rank
    from public.knowledge_items item
    join public.knowledge_embeddings embedding on embedding.item_id = item.id
    where item.space_id = any(target_space_ids)
      and item.status = 'active'
      and item.is_current
      and embedding.model_id = query_model_id
    order by rank
    limit least(greatest(match_count, 1) * 4, 40)
  ),
  fused as (
    select
      coalesce(full_text.id, semantic.id) as id,
      coalesce(1.0 / (50 + full_text.rank), 0.0)
      + coalesce(1.0 / (50 + semantic.rank), 0.0) as score
    from full_text
    full outer join semantic on semantic.id = full_text.id
  )
  select
    item.id,
    item.space_id,
    item.title,
    item.content,
    item.kind,
    item.language_code,
    fused.score
  from fused
  join public.knowledge_items item on item.id = fused.id
  order by fused.score desc
  limit least(greatest(match_count, 1), 30);
$$;

revoke all on function public.search_knowledge(text, extensions.vector, text, uuid[], integer)
  from public, anon;
grant execute on function public.search_knowledge(text, extensions.vector, text, uuid[], integer)
  to authenticated;
