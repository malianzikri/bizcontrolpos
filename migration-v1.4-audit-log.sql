-- BizControl Online V1.3 -> V1.4 migration
-- AUDIT LOG: read-only activity history for products, stock, sales, expenses and security actions.
-- Run once in Supabase SQL Editor AFTER V1.3 migration.

create table if not exists public.audit_logs (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  actor_user_id uuid references auth.users(id) on delete set null,
  actor_email text,
  action text not null check (action in ('CREATE','UPDATE','DELETE','SECURITY')),
  module text not null,
  record_id uuid,
  record_label text,
  before_data jsonb,
  after_data jsonb,
  created_at timestamptz not null default now()
);

create index if not exists idx_audit_logs_business_created
  on public.audit_logs (business_id, created_at desc);
create index if not exists idx_audit_logs_business_module
  on public.audit_logs (business_id, module, created_at desc);

alter table public.audit_logs enable row level security;

drop policy if exists "audit select owner admin" on public.audit_logs;
create policy "audit select owner admin"
on public.audit_logs for select
using (
  exists(select 1 from public.businesses b where b.id=business_id and b.owner_id=auth.uid())
  or exists(
    select 1 from public.business_members m
    where m.business_id=business_id
      and m.user_id=auth.uid()
      and m.role in ('owner','admin')
  )
);

grant select on public.audit_logs to authenticated;
revoke insert, update, delete on public.audit_logs from anon, authenticated;

create or replace function public.write_business_audit()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare
  bid uuid;
  rid uuid;
  module_name text;
  label text;
  before_json jsonb;
  after_json jsonb;
begin
  bid := case when tg_op='DELETE' then old.business_id else new.business_id end;
  rid := case when tg_op='DELETE' then old.id else new.id end;
  before_json := case when tg_op in ('UPDATE','DELETE') then to_jsonb(old) else null end;
  after_json := case when tg_op in ('INSERT','UPDATE') then to_jsonb(new) else null end;
  module_name := tg_table_name;

  if tg_table_name='products' then
    label := coalesce(case when tg_op='DELETE' then old.sku else new.sku end,'') || ' · ' || coalesce(case when tg_op='DELETE' then old.name else new.name end,'');
    -- A product UPDATE that only changes stock is easier to read as a Stock event.
    if tg_op='UPDATE'
       and new.stock is distinct from old.stock
       and (to_jsonb(new) - 'stock' - 'updated_at') = (to_jsonb(old) - 'stock' - 'updated_at') then
      module_name := 'stock';
    end if;
  elsif tg_table_name='sales' then
    label := coalesce(case when tg_op='DELETE' then old.invoice_no else new.invoice_no end,'') ||
      case when coalesce(case when tg_op='DELETE' then old.customer else new.customer end,'')<>''
        then ' · ' || coalesce(case when tg_op='DELETE' then old.customer else new.customer end,'')
        else '' end;
  elsif tg_table_name='expenses' then
    label := coalesce(case when tg_op='DELETE' then old.description else new.description end,'Biaya');
  else
    label := coalesce(rid::text,'Data');
  end if;

  insert into public.audit_logs(
    business_id, actor_user_id, actor_email, action, module,
    record_id, record_label, before_data, after_data, created_at
  ) values (
    bid,
    auth.uid(),
    coalesce(auth.jwt() ->> 'email','system'),
    case tg_op when 'INSERT' then 'CREATE' when 'UPDATE' then 'UPDATE' else 'DELETE' end,
    module_name,
    rid,
    label,
    before_json,
    after_json,
    now()
  );

  return null;
end;
$$;

revoke all on function public.write_business_audit() from public;

drop trigger if exists trg_audit_products on public.products;
create trigger trg_audit_products
after insert or update or delete on public.products
for each row execute function public.write_business_audit();

drop trigger if exists trg_audit_sales on public.sales;
create trigger trg_audit_sales
after insert or update or delete on public.sales
for each row execute function public.write_business_audit();

drop trigger if exists trg_audit_expenses on public.expenses;
create trigger trg_audit_expenses
after insert or update or delete on public.expenses
for each row execute function public.write_business_audit();

-- Replace V1.3 setter so changing the delete Security Key is also audited.
-- PIN and PIN hash are NEVER written into audit_logs.
create or replace function public.set_delete_pin(bid uuid, pin text)
returns boolean
language plpgsql
security definer
set search_path=public
as $$
declare
  existed boolean;
begin
  if auth.uid() is null then raise exception 'Harus login'; end if;
  if not exists(select 1 from public.businesses b where b.id=bid and b.owner_id=auth.uid()) then
    raise exception 'Hanya owner yang dapat mengatur Security Key';
  end if;
  if pin !~ '^[0-9]{6}$' then
    raise exception 'Security Key harus 6 digit angka';
  end if;

  existed := exists(select 1 from public.business_security s where s.business_id=bid);

  insert into public.business_security(business_id,delete_pin_hash,updated_at)
  values (bid,crypt(pin,gen_salt('bf')),now())
  on conflict (business_id) do update
    set delete_pin_hash=excluded.delete_pin_hash,updated_at=now();

  insert into public.audit_logs(
    business_id, actor_user_id, actor_email, action, module,
    record_id, record_label, before_data, after_data, created_at
  ) values (
    bid, auth.uid(), coalesce(auth.jwt() ->> 'email','system'),
    'SECURITY','security',null,'Security Key Hapus Data',
    jsonb_build_object('configured',existed),
    jsonb_build_object('configured',true),
    now()
  );

  return true;
end;
$$;

revoke all on function public.set_delete_pin(uuid,text) from public;
grant execute on function public.set_delete_pin(uuid,text) to authenticated;

-- Optional retention job can be added later. V1.4 keeps audit history indefinitely.
