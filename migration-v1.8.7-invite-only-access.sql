-- BizControl Online V1.8.7 — Invite-Only Access & Owner Provisioning Hardening
-- Run AFTER V1.8.6 migration.
-- Purpose:
-- 1) Public/self-created Auth users cannot create a BizControl business.
-- 2) New Owner access is provisioned only by trusted server-side Admin through owner_accounts.
-- 3) Existing owners are backfilled automatically.

begin;

create table if not exists public.owner_accounts (
  user_id uuid primary key references auth.users(id) on delete cascade,
  email text not null,
  status text not null default 'active',
  invited_by uuid references auth.users(id) on delete set null,
  invited_at timestamptz,
  activated_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint owner_accounts_status_check check (status in ('pending','active','disabled'))
);

create unique index if not exists owner_accounts_email_lower_uidx
  on public.owner_accounts ((lower(email)));
create index if not exists owner_accounts_status_idx
  on public.owner_accounts(status);

alter table public.owner_accounts enable row level security;
-- No browser role gets direct table access. Edge Functions use service_role.
revoke all on table public.owner_accounts from public, anon, authenticated;

-- Existing business owners remain authorized after this hardening migration.
insert into public.owner_accounts(user_id,email,status,activated_at,created_at,updated_at)
select distinct on (b.owner_id)
       b.owner_id,
       lower(u.email::text),
       'active',
       now(),
       coalesce(b.created_at,now()),
       now()
from public.businesses b
join auth.users u on u.id=b.owner_id
where u.email is not null
order by b.owner_id,b.created_at asc
on conflict (user_id) do update
set email=excluded.email,
    status=case when public.owner_accounts.status='disabled' then 'disabled' else 'active' end,
    activated_at=coalesce(public.owner_accounts.activated_at,excluded.activated_at),
    updated_at=now();

create or replace function public.can_create_business()
returns boolean
language sql
security definer
set search_path=pg_catalog,public,auth
stable
as $$
  select auth.uid() is not null and (
    exists(
      select 1 from public.owner_accounts oa
      where oa.user_id=auth.uid()
        and oa.status in ('pending','active')
    )
    or exists(
      select 1 from public.businesses b
      where b.owner_id=auth.uid()
    )
  );
$$;
revoke all on function public.can_create_business() from public,anon;
grant execute on function public.can_create_business() to authenticated;

create or replace function public.activate_owner_account()
returns boolean
language plpgsql
security definer
set search_path=pg_catalog,public,auth
as $$
begin
  if auth.uid() is null then
    raise exception 'Login diperlukan' using errcode='28000';
  end if;

  update public.owner_accounts
  set status='active',
      activated_at=coalesce(activated_at,now()),
      updated_at=now()
  where user_id=auth.uid()
    and status='pending';

  return exists(
    select 1 from public.owner_accounts
    where user_id=auth.uid() and status='active'
  );
end;
$$;
revoke all on function public.activate_owner_account() from public,anon;
grant execute on function public.activate_owner_account() to authenticated;

-- Harden first/additional business creation. A generic authenticated Auth user is no longer sufficient.
create or replace function public.create_business(p_name text)
returns table(
  id uuid,
  name text,
  address text,
  phone text,
  email text,
  city text,
  document_footer text,
  owner_id uuid,
  created_at timestamptz,
  updated_at timestamptz,
  allow_negative_stock boolean
)
language plpgsql
security definer
set search_path=pg_catalog,public,auth,extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_name text := btrim(coalesce(p_name,''));
begin
  if v_uid is null then
    raise exception 'Sesi login tidak valid. Silakan login ulang.' using errcode='28000';
  end if;

  if not public.can_create_business() then
    raise exception 'Akun ini tidak memiliki izin membuat bisnis. Hubungi Admin BizControl.' using errcode='42501';
  end if;

  if length(v_name) < 2 then
    raise exception 'Nama bisnis minimal 2 karakter' using errcode='22023';
  end if;
  if length(v_name) > 120 then
    raise exception 'Nama bisnis maksimal 120 karakter' using errcode='22023';
  end if;

  return query
  insert into public.businesses as b(name,owner_id,allow_negative_stock)
  values(v_name,v_uid,false)
  returning b.id,b.name,b.address,b.phone,b.email,b.city,b.document_footer,
            b.owner_id,b.created_at,b.updated_at,b.allow_negative_stock;
end;
$$;
revoke all on function public.create_business(text) from public,anon,authenticated;
grant execute on function public.create_business(text) to authenticated;

-- Keep browser-side direct ownership creation closed.
revoke insert(name,owner_id,allow_negative_stock) on public.businesses from authenticated;

commit;
