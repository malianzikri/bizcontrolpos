-- BizControl Online V1.17 - Production Readiness
-- Prerequisite: V1.9 purchasing + V1.10-V1.16 POS suite.
-- Additive migration: does not DROP/TRUNCATE transactional tables.

begin;

create table if not exists public.saas_plans (
  code text primary key,
  name text not null,
  max_team_users integer,
  max_products integer,
  features jsonb not null default '{}'::jsonb,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

insert into public.saas_plans(code,name,max_team_users,max_products,features)
values
  ('starter','Starter',2,500,'{"pos":true,"reports":true,"purchasing":true,"recipe":true,"loyalty":true}'::jsonb),
  ('business','Business',5,3000,'{"pos":true,"reports":true,"purchasing":true,"recipe":true,"loyalty":true}'::jsonb),
  ('pro','Pro',null,null,'{"pos":true,"reports":true,"purchasing":true,"recipe":true,"loyalty":true,"priority_support":true}'::jsonb)
on conflict(code) do update set
  name=excluded.name,
  max_team_users=excluded.max_team_users,
  max_products=excluded.max_products,
  features=excluded.features,
  active=true,
  updated_at=now();

create table if not exists public.business_subscriptions (
  business_id uuid primary key references public.businesses(id) on delete cascade,
  plan_code text not null references public.saas_plans(code),
  status text not null default 'trial' check(status in('trial','active','grace','expired','suspended')),
  started_at timestamptz not null default now(),
  period_end timestamptz,
  grace_until timestamptz,
  source text not null default 'system',
  notes text,
  updated_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.business_onboarding (
  business_id uuid primary key references public.businesses(id) on delete cascade,
  printer_tested_at timestamptz,
  dismissed_at timestamptz,
  completed_at timestamptz,
  updated_at timestamptz not null default now()
);

create table if not exists public.app_events (
  id uuid primary key default gen_random_uuid(),
  business_id uuid references public.businesses(id) on delete cascade,
  user_id uuid,
  level text not null check(level in('info','warning','error')),
  source text not null default 'web',
  code text,
  message text not null,
  context jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index if not exists app_events_business_created_idx on public.app_events(business_id,created_at desc);
create index if not exists app_events_level_created_idx on public.app_events(level,created_at desc);

create table if not exists public.backup_events (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  user_id uuid,
  event_type text not null check(event_type in('export_json','verify_json','restore_requested','restore_completed')),
  backup_version text,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index if not exists backup_events_business_created_idx on public.backup_events(business_id,created_at desc);

-- Existing businesses are grandfathered as active until Admin Sistem sets an expiry.
insert into public.business_subscriptions(business_id,plan_code,status,period_end,source,notes)
select b.id,'business','active',null,'v1.17_migration','Existing business grandfathered during V1.17 migration'
from public.businesses b
on conflict(business_id) do nothing;

insert into public.business_onboarding(business_id)
select b.id from public.businesses b
on conflict(business_id) do nothing;

create or replace function public.v117_effective_subscription_status(p_bid uuid)
returns text
language plpgsql
stable
security definer
set search_path=pg_catalog,public,auth,extensions
as $$
declare s public.business_subscriptions%rowtype;
begin
  select * into s from public.business_subscriptions where business_id=p_bid;
  if not found then return 'expired'; end if;
  if s.status='suspended' then return 'suspended'; end if;
  if s.status='expired' then return 'expired'; end if;
  if s.status='grace' then
    if s.grace_until is null or s.grace_until>=now() then return 'grace'; end if;
    return 'expired';
  end if;
  if s.period_end is null or s.period_end>=now() then return s.status; end if;
  if s.grace_until is not null and s.grace_until>=now() then return 'grace'; end if;
  return 'expired';
end $$;

create or replace function public.get_business_entitlement_v117(p_bid uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,public,auth,extensions
as $$
declare
  s public.business_subscriptions%rowtype;
  p public.saas_plans%rowtype;
  r text;
begin
  if public.business_role(p_bid)='none' then raise exception 'Tidak memiliki akses bisnis'; end if;
  select * into s from public.business_subscriptions where business_id=p_bid;
  if not found then return jsonb_build_object('business_id',p_bid,'status','expired','effective_status','expired','can_write',false); end if;
  select * into p from public.saas_plans where code=s.plan_code;
  r:=public.v117_effective_subscription_status(p_bid);
  return jsonb_build_object(
    'business_id',p_bid,
    'plan_code',s.plan_code,
    'plan_name',coalesce(p.name,s.plan_code),
    'status',s.status,
    'effective_status',r,
    'can_write',r in('trial','active','grace'),
    'started_at',s.started_at,
    'period_end',s.period_end,
    'grace_until',s.grace_until,
    'max_team_users',p.max_team_users,
    'max_products',p.max_products,
    'features',coalesce(p.features,'{}'::jsonb)
  );
end $$;

create or replace function public.v117_assert_business_writable()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,public,auth,extensions
as $$
declare bid uuid; effective text; jwt_role text;
begin
  jwt_role:=coalesce((nullif(current_setting('request.jwt.claims',true),'')::jsonb ->> 'role'),'');
  if jwt_role='service_role' then if tg_op='DELETE' then return old; else return new; end if; end if;
  if tg_op='DELETE' then bid:=old.business_id; else bid:=new.business_id; end if;
  if bid is null then if tg_op='DELETE' then return old; else return new; end if; end if;
  effective:=public.v117_effective_subscription_status(bid);
  if effective not in('trial','active','grace') then
    raise exception 'SUBSCRIPTION_READ_ONLY: masa aktif BizControl tidak aktif (%). Data tetap dapat dibaca/backup, tetapi perubahan diblokir.',effective;
  end if;
  if tg_op='DELETE' then return old; else return new; end if;
end $$;

-- Add read-only expiry guard to business data. Service-role maintenance remains allowed.
do $$
declare t text; trig text;
begin
  foreach t in array array[
    'products','sales','sale_items','payments','expenses','suppliers','purchase_orders','purchase_order_items',
    'cashier_shifts','cash_movements','sale_adjustments','stock_adjustments','product_recipes','customers','loyalty_ledger'
  ] loop
    if to_regclass('public.'||t) is not null then
      trig:='v117_subscription_guard_'||t;
      execute format('drop trigger if exists %I on public.%I',trig,t);
      execute format('create trigger %I before insert or update or delete on public.%I for each row execute function public.v117_assert_business_writable()',trig,t);
    end if;
  end loop;
end $$;


-- Membership changes are also write operations, but DELETE remains allowed so an Owner can revoke access even when expired.
drop trigger if exists v117_subscription_guard_members on public.business_members;
create trigger v117_subscription_guard_members before insert or update on public.business_members for each row execute function public.v117_assert_business_writable();

create or replace function public.v117_enforce_team_limit()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,public,auth,extensions
as $$
declare lim integer; used_count integer; effective text;
begin
  effective:=public.v117_effective_subscription_status(new.business_id);
  if effective not in('trial','active','grace') then
    raise exception 'SUBSCRIPTION_READ_ONLY: masa aktif BizControl tidak aktif';
  end if;
  select p.max_team_users into lim
  from public.business_subscriptions s join public.saas_plans p on p.code=s.plan_code
  where s.business_id=new.business_id;
  if lim is null then return new; end if;
  select 1+count(*) into used_count
  from public.business_members bm
  where bm.business_id=new.business_id
    and coalesce(bm.status,'active')<>'disabled'
    and (tg_op='INSERT' or bm.user_id<>new.user_id);
  if used_count>=lim then
    raise exception 'PLAN_USER_LIMIT: paket saat ini maksimal % user termasuk Owner',lim;
  end if;
  return new;
end $$;

drop trigger if exists v117_team_limit on public.business_members;
create trigger v117_team_limit before insert on public.business_members for each row execute function public.v117_enforce_team_limit();

create or replace function public.v117_enforce_product_limit()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,public,auth,extensions
as $$
declare lim integer; used_count integer;
begin
  select p.max_products into lim
  from public.business_subscriptions s join public.saas_plans p on p.code=s.plan_code
  where s.business_id=new.business_id;
  if lim is null then return new; end if;
  select count(*) into used_count from public.products where business_id=new.business_id;
  if used_count>=lim then raise exception 'PLAN_PRODUCT_LIMIT: paket saat ini maksimal % produk',lim; end if;
  return new;
end $$;

drop trigger if exists v117_product_limit on public.products;
create trigger v117_product_limit before insert on public.products for each row execute function public.v117_enforce_product_limit();


create or replace function public.v117_enforce_business_limit()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,public,auth,extensions
as $$
declare jwt_role text; owner_uid uuid; existing_count integer;
begin
  jwt_role:=coalesce((nullif(current_setting('request.jwt.claims',true),'')::jsonb ->> 'role'),'');
  if jwt_role='service_role' then return new; end if;
  owner_uid:=auth.uid();
  if owner_uid is null then return new; end if;
  select count(*) into existing_count from public.businesses where owner_id=owner_uid;
  if existing_count>=1 then raise exception 'BUSINESS_LIMIT: V1.17 Cloud mendukung 1 bisnis per Owner. Multi-outlet akan menggunakan modul khusus.'; end if;
  return new;
end $$;

drop trigger if exists v117_business_limit on public.businesses;
create trigger v117_business_limit before insert on public.businesses for each row execute function public.v117_enforce_business_limit();

create or replace function public.v117_new_business_defaults()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,public,auth,extensions
as $$
begin
  insert into public.business_subscriptions(business_id,plan_code,status,started_at,period_end,grace_until,source,notes)
  values(new.id,'starter','trial',now(),now()+interval '14 days',now()+interval '17 days','auto_trial','14-day trial + 3-day grace')
  on conflict(business_id) do nothing;
  insert into public.business_onboarding(business_id) values(new.id) on conflict(business_id) do nothing;
  return new;
end $$;

drop trigger if exists v117_business_defaults on public.businesses;
create trigger v117_business_defaults after insert on public.businesses for each row execute function public.v117_new_business_defaults();

create or replace function public.log_client_event_v117(
  p_bid uuid,
  p_level text,
  p_code text,
  p_message text,
  p_context jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path=pg_catalog,public,auth,extensions
as $$
declare v_id uuid;
begin
  if public.business_role(p_bid)='none' then raise exception 'Tidak memiliki akses bisnis'; end if;
  if p_level not in('info','warning','error') then p_level:='error'; end if;
  insert into public.app_events(business_id,user_id,level,source,code,message,context)
  values(p_bid,auth.uid(),p_level,'web',left(coalesce(p_code,''),120),left(coalesce(p_message,'Unknown error'),1000),coalesce(p_context,'{}'::jsonb))
  returning id into v_id;
  return v_id;
end $$;

create or replace function public.record_backup_event_v117(
  p_bid uuid,
  p_event_type text,
  p_backup_version text default null,
  p_details jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path=pg_catalog,public,auth,extensions
as $$
declare v_id uuid;
begin
  if public.business_role(p_bid) not in('owner','admin','finance') then raise exception 'Tidak diizinkan'; end if;
  if p_event_type not in('export_json','verify_json','restore_requested','restore_completed') then raise exception 'Event backup tidak valid'; end if;
  insert into public.backup_events(business_id,user_id,event_type,backup_version,details)
  values(p_bid,auth.uid(),p_event_type,left(coalesce(p_backup_version,''),40),coalesce(p_details,'{}'::jsonb))
  returning id into v_id;
  return v_id;
end $$;

-- RLS / grants. Default privileges were hardened in older migrations, so grants are explicit.
alter table public.saas_plans enable row level security;
alter table public.business_subscriptions enable row level security;
alter table public.business_onboarding enable row level security;
alter table public.app_events enable row level security;
alter table public.backup_events enable row level security;

drop policy if exists "v117 plans read" on public.saas_plans;
create policy "v117 plans read" on public.saas_plans for select to authenticated using(active=true);

drop policy if exists "v117 subscription read" on public.business_subscriptions;
create policy "v117 subscription read" on public.business_subscriptions for select to authenticated using(public.business_role(business_id)<>'none');

drop policy if exists "v117 onboarding read" on public.business_onboarding;
create policy "v117 onboarding read" on public.business_onboarding for select to authenticated using(public.business_role(business_id)<>'none');
drop policy if exists "v117 onboarding update" on public.business_onboarding;
create policy "v117 onboarding update" on public.business_onboarding for update to authenticated
  using(public.has_business_role(business_id,array['owner','admin']))
  with check(public.has_business_role(business_id,array['owner','admin']));

drop policy if exists "v117 app events read" on public.app_events;
create policy "v117 app events read" on public.app_events for select to authenticated using(public.has_business_role(business_id,array['owner','admin']));

drop policy if exists "v117 backup events read" on public.backup_events;
create policy "v117 backup events read" on public.backup_events for select to authenticated using(public.has_business_role(business_id,array['owner','admin','finance']));

grant select on public.saas_plans to authenticated;
grant select on public.business_subscriptions to authenticated;
grant select on public.business_onboarding to authenticated;
grant update(printer_tested_at,dismissed_at,completed_at,updated_at) on public.business_onboarding to authenticated;
grant select on public.app_events to authenticated;
grant select on public.backup_events to authenticated;
grant select,insert,update,delete on public.saas_plans to service_role;
grant select,insert,update,delete on public.business_subscriptions to service_role;
grant select,insert,update,delete on public.business_onboarding to service_role;
grant select,insert,update,delete on public.app_events to service_role;
grant select,insert,update,delete on public.backup_events to service_role;

revoke all on function public.v117_effective_subscription_status(uuid) from public,anon,authenticated;
revoke all on function public.get_business_entitlement_v117(uuid) from public,anon,authenticated;
revoke all on function public.log_client_event_v117(uuid,text,text,text,jsonb) from public,anon,authenticated;
revoke all on function public.record_backup_event_v117(uuid,text,text,jsonb) from public,anon,authenticated;
grant execute on function public.get_business_entitlement_v117(uuid) to authenticated;
grant execute on function public.log_client_event_v117(uuid,text,text,text,jsonb) to authenticated;
grant execute on function public.record_backup_event_v117(uuid,text,text,jsonb) to authenticated;

-- Keep internal trigger/helper functions unavailable as browser RPCs.
revoke all on function public.v117_assert_business_writable() from public,anon,authenticated;
revoke all on function public.v117_enforce_team_limit() from public,anon,authenticated;
revoke all on function public.v117_enforce_product_limit() from public,anon,authenticated;
revoke all on function public.v117_new_business_defaults() from public,anon,authenticated;
revoke all on function public.v117_enforce_business_limit() from public,anon,authenticated;

commit;
