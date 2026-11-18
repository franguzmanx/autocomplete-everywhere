-- Content-free account semaphore shared by all API instances.
create table public.context_background_leases (
 user_id text not null,
 slot smallint not null check(slot in (1,2)),
 lease_id uuid not null unique,
 expires_at timestamptz not null,
 primary key(user_id,slot)
);
alter table public.context_background_leases enable row level security;
create policy own_context_leases on public.context_background_leases for all to authenticated
 using (user_id=(select private.current_user_id())) with check (user_id=(select private.current_user_id()));
grant select,insert,delete on public.context_background_leases to authenticated;
create function public.acquire_context_background_lease(target_lease uuid) returns boolean
language plpgsql security invoker set search_path='' as $$
declare subject text := (select private.current_user_id()); selected_slot smallint;
begin
 if subject is null then raise exception 'authenticated user required' using errcode='42501'; end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(subject,917));
 delete from public.context_background_leases where user_id=subject and expires_at<=clock_timestamp();
 select candidate into selected_slot from generate_series(1,2) candidate
 where not exists(select 1 from public.context_background_leases where user_id=subject and slot=candidate) limit 1;
 if selected_slot is null then return false; end if;
 insert into public.context_background_leases(user_id,slot,lease_id,expires_at)
 values(subject,selected_slot,target_lease,clock_timestamp()+interval '30 seconds');
 return true;
end;
$$;
revoke all on function public.acquire_context_background_lease(uuid) from public;
grant execute on function public.acquire_context_background_lease(uuid) to authenticated;
