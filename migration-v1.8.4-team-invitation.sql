-- BizControl Online V1.8.4 — Team Invitation Flow
-- Run AFTER V1.8.3 staging hotfix.
-- Adds pending/active membership state, first-login activation, and role-safe revocation.

begin;

alter table public.business_members
  add column if not exists status text not null default 'active';
alter table public.business_members
  add column if not exists invited_by uuid references auth.users(id) on delete set null;
alter table public.business_members
  add column if not exists invited_at timestamptz;
alter table public.business_members
  add column if not exists activated_at timestamptz;

-- Existing members were already usable before this migration, so keep them active.
update public.business_members
set status='active',
    activated_at=coalesce(activated_at,created_at)
where status is null or status='active';

create index if not exists idx_business_members_user_status
  on public.business_members(user_id,status);
create index if not exists idx_business_members_business_status
  on public.business_members(business_id,status);

-- Named constraint so future migrations can reason about it safely.
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname='business_members_status_check'
      and conrelid='public.business_members'::regclass
  ) then
    alter table public.business_members
      add constraint business_members_status_check
      check (status in ('pending','active'));
  end if;
end $$;

-- Only ACTIVE memberships grant access. Owner access is unchanged.
create or replace function public.business_role(bid uuid)
returns text
language sql
security definer
set search_path=pg_catalog,public,auth
stable
as $$
  select case
    when exists(
      select 1 from public.businesses b
      where b.id=bid and b.owner_id=auth.uid()
    ) then 'owner'
    else coalesce((
      select m.role
      from public.business_members m
      where m.business_id=bid
        and m.user_id=auth.uid()
        and m.status='active'
      limit 1
    ),'none')
  end;
$$;

revoke all on function public.business_role(uuid) from public,anon;
grant execute on function public.business_role(uuid) to authenticated;

create or replace function public.can_access_business(bid uuid)
returns boolean
language sql
security definer
set search_path=pg_catalog,public,auth
stable
as $$
  select public.business_role(bid) <> 'none';
$$;
revoke all on function public.can_access_business(uuid) from public,anon;
grant execute on function public.can_access_business(uuid) to authenticated;

-- A pending invite becomes active only after that Auth user successfully signs in.
create or replace function public.activate_pending_memberships()
returns integer
language plpgsql
security definer
set search_path=pg_catalog,public,auth
as $$
declare affected integer;
begin
  if auth.uid() is null then
    raise exception 'Login diperlukan';
  end if;

  update public.business_members
  set status='active',
      activated_at=coalesce(activated_at,now())
  where user_id=auth.uid()
    and status='pending';

  get diagnostics affected=row_count;
  return affected;
end;
$$;
revoke all on function public.activate_pending_memberships() from public,anon;
grant execute on function public.activate_pending_memberships() to authenticated;

-- Return invitation state to the Team & Role screen.
drop function if exists public.list_business_members(uuid);
create function public.list_business_members(bid uuid)
returns table(
  user_id uuid,
  email text,
  role text,
  status text,
  created_at timestamptz,
  invited_at timestamptz,
  activated_at timestamptz
)
language plpgsql
security definer
set search_path=pg_catalog,public,auth
stable
as $$
begin
  if auth.uid() is null or not public.has_business_role(bid,array['owner','admin']) then
    raise exception 'Hanya owner/admin yang dapat melihat tim';
  end if;

  return query
    select m.user_id,
           u.email::text,
           m.role,
           m.status,
           m.created_at,
           m.invited_at,
           m.activated_at
    from public.business_members m
    join auth.users u on u.id=m.user_id
    where m.business_id=bid
    order by m.created_at asc;
end;
$$;
revoke all on function public.list_business_members(uuid) from public,anon;
grant execute on function public.list_business_members(uuid) to authenticated;

-- Legacy "email must already be registered" path is disabled for browser clients.
-- V1.8.4 uses the server-side team-invite Edge Function instead.
revoke execute on function public.add_business_member_by_email(uuid,text,text) from authenticated;

-- Owner can still change role and revoke membership via existing hardened RPCs.
revoke all on function public.update_business_member_role(uuid,uuid,text) from public,anon;
revoke all on function public.remove_business_member(uuid,uuid) from public,anon;
grant execute on function public.update_business_member_role(uuid,uuid,text) to authenticated;
grant execute on function public.remove_business_member(uuid,uuid) to authenticated;

commit;
