-- BizControl Online V1.10 -> V1.16 POS Operations Suite
-- Jalankan SETELAH migration-v1.9-purchasing.sql pada database existing.
-- Migration additive: tidak menghapus data transaksi lama.
-- Features: cashier shift, refund/void, stock opname, barcode/variant,
-- promo/tax/service, recipe/BOM, CRM/membership/loyalty point.

begin;

-- =========================================================
-- V1.10 — CASHIER SHIFT
-- =========================================================
create table if not exists public.cashier_shifts (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  user_id uuid references auth.users(id) on delete set null,
  cashier_name text,
  opened_at timestamptz not null default now(),
  closed_at timestamptz,
  opening_cash numeric(18,2) not null default 0 check(opening_cash>=0),
  expected_cash numeric(18,2),
  closing_cash numeric(18,2),
  difference numeric(18,2),
  status text not null default 'open' check(status in ('open','closed')),
  notes text,
  created_at timestamptz not null default now()
);
create unique index if not exists cashier_shifts_one_open_per_business on public.cashier_shifts(business_id) where status='open';
create index if not exists cashier_shifts_business_opened_idx on public.cashier_shifts(business_id,opened_at desc);

create table if not exists public.cash_movements (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  shift_id uuid not null references public.cashier_shifts(id) on delete cascade,
  type text not null check(type in ('in','out')),
  amount numeric(18,2) not null check(amount>0),
  notes text not null,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);
create index if not exists cash_movements_shift_idx on public.cash_movements(business_id,shift_id,created_at);

-- =========================================================
-- V1.13 / V1.14 / V1.16 — additive columns on core records
-- =========================================================
alter table public.businesses add column if not exists tax_rate_default numeric(8,3) not null default 0;
alter table public.businesses add column if not exists service_rate_default numeric(8,3) not null default 0;
alter table public.businesses add column if not exists loyalty_spend_per_point numeric(18,2) not null default 10000;
alter table public.businesses add column if not exists loyalty_point_value numeric(18,2) not null default 100;

alter table public.products add column if not exists barcode text;
alter table public.products add column if not exists variant_name text;
alter table public.products add column if not exists inventory_mode text not null default 'self';
update public.products set inventory_mode='none' where category='Jasa' and coalesce(inventory_mode,'self')='self';
create unique index if not exists products_business_barcode_uidx on public.products(business_id,barcode) where barcode is not null and btrim(barcode)<>'';

-- =========================================================
-- V1.16 — CRM / MEMBERSHIP
-- =========================================================
create table if not exists public.customers (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  client_request_id uuid,
  member_no text,
  name text not null,
  phone text not null,
  email text,
  birthday date,
  address text,
  notes text,
  points_balance integer not null default 0 check(points_balance>=0),
  total_spend numeric(18,2) not null default 0,
  visit_count integer not null default 0,
  last_visit date,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(business_id,phone),
  unique(business_id,member_no)
);
create unique index if not exists customers_request_uidx on public.customers(business_id,client_request_id) where client_request_id is not null;

create or replace function public.customer_member_no_v116()
returns trigger language plpgsql security definer
set search_path to pg_catalog,public,auth,extensions
as $$
begin
  if new.member_no is null or btrim(new.member_no)='' then
    new.member_no:='MBR-'||upper(substr(replace(new.id::text,'-',''),1,8));
  end if;
  new.updated_at:=now();
  return new;
end $$;
drop trigger if exists trg_customer_member_no_v116 on public.customers;
create trigger trg_customer_member_no_v116 before insert or update on public.customers for each row execute function public.customer_member_no_v116();

create table if not exists public.loyalty_ledger (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  customer_id uuid not null references public.customers(id) on delete cascade,
  sale_id uuid references public.sales(id) on delete set null,
  points integer not null,
  type text not null check(type in ('earn','redeem','refund','manual')),
  notes text,
  created_at timestamptz not null default now()
);
create index if not exists loyalty_ledger_customer_idx on public.loyalty_ledger(business_id,customer_id,created_at desc);

-- =========================================================
-- V1.15 — RECIPE / BOM
-- =========================================================
create table if not exists public.product_recipes (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete cascade,
  ingredient_product_id uuid not null references public.products(id),
  qty_per_unit numeric(18,4) not null check(qty_per_unit>0),
  created_at timestamptz not null default now(),
  unique(product_id,ingredient_product_id),
  check(product_id<>ingredient_product_id)
);
create index if not exists product_recipes_business_product_idx on public.product_recipes(business_id,product_id);

-- =========================================================
-- V1.11 — REFUND / VOID
-- =========================================================
create table if not exists public.sale_adjustments (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  sale_id uuid not null references public.sales(id) on delete cascade,
  type text not null check(type in ('refund','void')),
  date date not null default current_date,
  amount numeric(18,2) not null default 0 check(amount>=0),
  cost_amount numeric(18,2) not null default 0 check(cost_amount>=0),
  payment_method text,
  reason text,
  items jsonb not null default '[]'::jsonb,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);
create index if not exists sale_adjustments_sale_idx on public.sale_adjustments(business_id,sale_id,created_at desc);

alter table public.sales add column if not exists subtotal numeric(18,2);
alter table public.sales add column if not exists promo_name text;
alter table public.sales add column if not exists promo_discount numeric(18,2) not null default 0;
alter table public.sales add column if not exists loyalty_discount numeric(18,2) not null default 0;
alter table public.sales add column if not exists service_rate numeric(8,3) not null default 0;
alter table public.sales add column if not exists service_amount numeric(18,2) not null default 0;
alter table public.sales add column if not exists tax_rate numeric(8,3) not null default 0;
alter table public.sales add column if not exists tax_amount numeric(18,2) not null default 0;
alter table public.sales add column if not exists refund_total numeric(18,2) not null default 0;
alter table public.sales add column if not exists refund_cost numeric(18,2) not null default 0;
alter table public.sales add column if not exists status text not null default 'completed';
alter table public.sales add column if not exists customer_id uuid references public.customers(id) on delete set null;
alter table public.sales add column if not exists points_earned integer not null default 0;
alter table public.sales add column if not exists points_redeemed integer not null default 0;
alter table public.sales add column if not exists cashier_shift_id uuid references public.cashier_shifts(id) on delete set null;

update public.sales s set subtotal=coalesce(s.subtotal,x.subtotal,s.total+s.discount)
from (select sale_id,sum(line_total) subtotal from public.sale_items group by sale_id) x
where x.sale_id=s.id and s.subtotal is null;
update public.sales set subtotal=coalesce(subtotal,total+discount),promo_discount=coalesce(promo_discount,discount),status=coalesce(status,'completed');

-- =========================================================
-- V1.12 — STOCK OPNAME
-- =========================================================
create table if not exists public.stock_adjustments (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  product_id uuid not null references public.products(id),
  before_stock numeric(18,4) not null,
  counted_stock numeric(18,4) not null check(counted_stock>=0),
  delta numeric(18,4) not null,
  reason text not null,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);
create index if not exists stock_adjustments_product_idx on public.stock_adjustments(business_id,product_id,created_at desc);

-- =========================================================
-- RLS / GRANTS
-- =========================================================
alter table public.cashier_shifts enable row level security;
alter table public.cash_movements enable row level security;
alter table public.customers enable row level security;
alter table public.loyalty_ledger enable row level security;
alter table public.product_recipes enable row level security;
alter table public.sale_adjustments enable row level security;
alter table public.stock_adjustments enable row level security;

revoke all on public.cashier_shifts,public.cash_movements,public.customers,public.loyalty_ledger,public.product_recipes,public.sale_adjustments,public.stock_adjustments from anon,authenticated;
grant select on public.cashier_shifts,public.cash_movements,public.loyalty_ledger,public.product_recipes,public.sale_adjustments,public.stock_adjustments to authenticated;
-- CRM mutations are column-limited so cashier cannot alter points/total_spend/visit counters directly.
grant select on public.customers to authenticated;
grant insert(business_id,client_request_id,name,phone,email,birthday,address,notes,active) on public.customers to authenticated;
grant update(name,phone,email,birthday,address,notes,active) on public.customers to authenticated;

-- New V1.13/V1.14/V1.16 columns must be exposed explicitly because V1.8 hardening uses column-level grants.
grant insert(barcode,variant_name,inventory_mode) on public.products to authenticated;
grant update(barcode,variant_name,inventory_mode) on public.products to authenticated;
grant update(tax_rate_default,service_rate_default,loyalty_spend_per_point,loyalty_point_value) on public.businesses to authenticated;

-- Purchasing V1.9 is deployed after default privileges were hardened. Make required Data API rights explicit.
revoke all on public.suppliers,public.purchase_orders,public.purchase_order_items from anon,authenticated;
grant select on public.suppliers to authenticated;
grant insert(business_id,name,client_request_id,contact_person,phone,email,address) on public.suppliers to authenticated;
grant update(name,contact_person,phone,email,address) on public.suppliers to authenticated;
grant select on public.purchase_orders to authenticated;
grant update(paid_amount) on public.purchase_orders to authenticated;
grant select on public.purchase_order_items to authenticated;

drop policy if exists "shift read v116" on public.cashier_shifts;
create policy "shift read v116" on public.cashier_shifts for select to authenticated using(public.has_business_role(business_id,array['owner','admin','cashier','finance']));
drop policy if exists "cash movement read v116" on public.cash_movements;
create policy "cash movement read v116" on public.cash_movements for select to authenticated using(public.has_business_role(business_id,array['owner','admin','cashier','finance']));
drop policy if exists "customer read v116" on public.customers;
create policy "customer read v116" on public.customers for select to authenticated using(public.has_business_role(business_id,array['owner','admin','cashier','finance']));
drop policy if exists "customer insert v116" on public.customers;
create policy "customer insert v116" on public.customers for insert to authenticated with check(public.has_business_role(business_id,array['owner','admin','cashier']));
drop policy if exists "customer update v116" on public.customers;
create policy "customer update v116" on public.customers for update to authenticated using(public.has_business_role(business_id,array['owner','admin','cashier'])) with check(public.has_business_role(business_id,array['owner','admin','cashier']));
drop policy if exists "loyalty read v116" on public.loyalty_ledger;
create policy "loyalty read v116" on public.loyalty_ledger for select to authenticated using(public.has_business_role(business_id,array['owner','admin','cashier','finance']));
drop policy if exists "recipe read v116" on public.product_recipes;
create policy "recipe read v116" on public.product_recipes for select to authenticated using(public.has_business_role(business_id,array['owner','admin','cashier','finance','warehouse','staff']));
drop policy if exists "adjustment read v116" on public.sale_adjustments;
create policy "adjustment read v116" on public.sale_adjustments for select to authenticated using(public.has_business_role(business_id,array['owner','admin','finance']));
drop policy if exists "stock adjustment read v116" on public.stock_adjustments;
create policy "stock adjustment read v116" on public.stock_adjustments for select to authenticated using(public.has_business_role(business_id,array['owner','admin','finance','warehouse']));

-- =========================================================
-- RECIPE COST HELPER
-- Recipe product HPP follows the current ingredient formula at sale time.
-- =========================================================
create or replace function public.product_unit_cost_v116(p_bid uuid,p_product_id uuid)
returns numeric language sql stable security definer
set search_path to pg_catalog,public,auth,extensions
as $$
  select case
    when coalesce(p.inventory_mode,case when p.category='Jasa' then 'none' else 'self' end)='recipe'
      then coalesce((select sum(pr.qty_per_unit*coalesce(i.cost,0)) from public.product_recipes pr join public.products i on i.id=pr.ingredient_product_id and i.business_id=pr.business_id where pr.business_id=p_bid and pr.product_id=p.id),coalesce(p.cost,0))
    else coalesce(p.cost,0)
  end
  from public.products p where p.id=p_product_id and p.business_id=p_bid
$$;
revoke all on function public.product_unit_cost_v116(uuid,uuid) from public,anon,authenticated;

-- =========================================================
-- INVENTORY HELPERS: self stock / recipe stock / no stock
-- qty_delta positive = restore/add, negative = consume
-- =========================================================
create or replace function public.adjust_product_inventory_v116(p_bid uuid,p_product_id uuid,p_qty_delta numeric)
returns void language plpgsql security definer
set search_path to pg_catalog,public,auth,extensions
as $$
declare v_mode text; v_category text; r record;
begin
  select coalesce(inventory_mode,case when category='Jasa' then 'none' else 'self' end),category into v_mode,v_category
  from public.products where id=p_product_id and business_id=p_bid;
  if not found then raise exception 'Produk tidak ditemukan'; end if;
  if v_category='Jasa' or v_mode='none' then return; end if;
  if v_mode='recipe' then
    for r in select ingredient_product_id,qty_per_unit from public.product_recipes where business_id=p_bid and product_id=p_product_id loop
      update public.products set stock=coalesce(stock,0)+(p_qty_delta*r.qty_per_unit),updated_at=now()
      where id=r.ingredient_product_id and business_id=p_bid;
    end loop;
  else
    update public.products set stock=coalesce(stock,0)+p_qty_delta,updated_at=now() where id=p_product_id and business_id=p_bid;
  end if;
end $$;
revoke all on function public.adjust_product_inventory_v116(uuid,uuid,numeric) from public,anon,authenticated;

create or replace function public.prepare_sale_item_v186()
returns trigger language plpgsql security definer
set search_path to pg_catalog,public,auth,extensions
as $$
declare
  v_name text;v_unit text;v_cost numeric;v_price numeric;v_business uuid;v_category text;v_stock numeric;v_mode text;
  v_allow_negative boolean:=false;v_needed numeric;v_ing record;
begin
  if new.qty is null or new.qty<=0 then raise exception 'Qty harus lebih dari 0'; end if;
  if tg_op='UPDATE' then
    if new.id is distinct from old.id or new.business_id is distinct from old.business_id or new.sale_id is distinct from old.sale_id or new.created_at is distinct from old.created_at then raise exception 'Field sistem item transaksi tidak boleh diubah'; end if;
    perform 1 from public.products where id in(old.product_id,new.product_id) order by id for update;
  else perform 1 from public.products where id=new.product_id for update; end if;
  select p.name,p.unit,p.cost,p.price,p.business_id,p.category,p.stock,coalesce(p.inventory_mode,case when p.category='Jasa' then 'none' else 'self' end)
  into v_name,v_unit,v_cost,v_price,v_business,v_category,v_stock,v_mode from public.products p where p.id=new.product_id;
  if v_mode='recipe' then v_cost:=coalesce(public.product_unit_cost_v116(new.business_id,new.product_id),v_cost,0); end if;
  if v_business is null or v_business<>new.business_id then raise exception 'Produk tidak ditemukan / beda bisnis'; end if;
  if not exists(select 1 from public.sales s where s.id=new.sale_id and s.business_id=new.business_id) then raise exception 'Invoice tidak ditemukan'; end if;
  select coalesce(b.allow_negative_stock,false) into v_allow_negative from public.businesses b where b.id=new.business_id;
  v_needed:=new.qty;
  if tg_op='UPDATE' and old.product_id=new.product_id then v_needed:=greatest(new.qty-old.qty,0); end if;
  if not v_allow_negative and v_needed>0 and v_category<>'Jasa' and v_mode<>'none' then
    if v_mode='recipe' then
      if not exists(select 1 from public.product_recipes where business_id=new.business_id and product_id=new.product_id) then raise exception 'Recipe % belum memiliki bahan baku',v_name; end if;
      for v_ing in select pr.qty_per_unit,p.stock,p.name from public.product_recipes pr join public.products p on p.id=pr.ingredient_product_id where pr.business_id=new.business_id and pr.product_id=new.product_id loop
        if coalesce(v_ing.stock,0)+0.000001 < v_needed*v_ing.qty_per_unit then raise exception 'Bahan baku % tidak cukup untuk %',v_ing.name,v_name; end if;
      end loop;
    elsif coalesce(v_stock,0)+0.000001 < v_needed then raise exception 'Stok % tidak cukup. Tersedia: %',v_name,v_stock; end if;
  end if;
  if tg_op='INSERT' or new.product_id is distinct from old.product_id then new.product_name:=case when coalesce((select variant_name from public.products where id=new.product_id),'')<>'' then v_name||' · '||(select variant_name from public.products where id=new.product_id) else v_name end;new.unit:=coalesce(v_unit,'pcs');new.unit_price:=coalesce(v_price,0);new.unit_cost:=coalesce(v_cost,0);
  else new.product_name:=old.product_name;new.unit:=old.unit;new.unit_price:=old.unit_price;new.unit_cost:=old.unit_cost;end if;
  new.line_total:=new.qty*new.unit_price;new.line_gross_profit:=new.line_total-(new.qty*new.unit_cost);new.updated_at:=now();return new;
end $$;
revoke all on function public.prepare_sale_item_v186() from public,anon,authenticated;

create or replace function public.apply_sale_item_stock_v116()
returns trigger language plpgsql security definer
set search_path to pg_catalog,public,auth,extensions
as $$
begin
  if tg_op='INSERT' then perform public.adjust_product_inventory_v116(new.business_id,new.product_id,-new.qty);return new;
  elsif tg_op='DELETE' then perform public.adjust_product_inventory_v116(old.business_id,old.product_id,old.qty);return old;
  elsif tg_op='UPDATE' then
    if old.product_id=new.product_id then
      if old.qty is distinct from new.qty then perform public.adjust_product_inventory_v116(new.business_id,new.product_id,old.qty-new.qty);end if;
    else perform public.adjust_product_inventory_v116(old.business_id,old.product_id,old.qty);perform public.adjust_product_inventory_v116(new.business_id,new.product_id,-new.qty);end if;
    return new;
  end if;return null;
end $$;
revoke all on function public.apply_sale_item_stock_v116() from public,anon,authenticated;
drop trigger if exists trg_apply_sale_item_stock_v186 on public.sale_items;
drop trigger if exists trg_apply_sale_item_stock_v116 on public.sale_items;
create trigger trg_apply_sale_item_stock_v116 after insert or update or delete on public.sale_items for each row execute function public.apply_sale_item_stock_v116();

-- =========================================================
-- V1.10 RPCs
-- =========================================================
create or replace function public.open_cashier_shift_v116(p_bid uuid,p_opening_cash numeric)
returns jsonb language plpgsql security definer set search_path to pg_catalog,public,auth,extensions
as $$ declare v_id uuid;
begin
 if not public.has_business_role(p_bid,array['owner','admin','cashier']) then return jsonb_build_object('ok',false,'error','Role tidak boleh membuka shift');end if;
 if exists(select 1 from public.cashier_shifts where business_id=p_bid and status='open') then return jsonb_build_object('ok',false,'error','Masih ada shift aktif');end if;
 insert into public.cashier_shifts(business_id,user_id,cashier_name,opening_cash,status) values(p_bid,auth.uid(),coalesce(auth.jwt()->>'email','Kasir'),greatest(coalesce(p_opening_cash,0),0),'open') returning id into v_id;
 return jsonb_build_object('ok',true,'shift_id',v_id);
end $$;
revoke all on function public.open_cashier_shift_v116(uuid,numeric) from public,anon;grant execute on function public.open_cashier_shift_v116(uuid,numeric) to authenticated;

create or replace function public.add_cash_movement_v116(p_bid uuid,p_shift_id uuid,p_type text,p_amount numeric,p_notes text)
returns jsonb language plpgsql security definer set search_path to pg_catalog,public,auth,extensions
as $$ begin
 if not public.has_business_role(p_bid,array['owner','admin','cashier']) then return jsonb_build_object('ok',false,'error','Tidak diizinkan');end if;
 if p_type not in('in','out') or coalesce(p_amount,0)<=0 then return jsonb_build_object('ok',false,'error','Data kas tidak valid');end if;
 if not exists(select 1 from public.cashier_shifts where id=p_shift_id and business_id=p_bid and status='open') then return jsonb_build_object('ok',false,'error','Shift tidak aktif');end if;
 insert into public.cash_movements(business_id,shift_id,type,amount,notes,created_by) values(p_bid,p_shift_id,p_type,p_amount,coalesce(nullif(p_notes,''),'Pergerakan kas'),auth.uid());return jsonb_build_object('ok',true);
end $$;
revoke all on function public.add_cash_movement_v116(uuid,uuid,text,numeric,text) from public,anon;grant execute on function public.add_cash_movement_v116(uuid,uuid,text,numeric,text) to authenticated;

create or replace function public.close_cashier_shift_v116(p_bid uuid,p_shift_id uuid,p_closing_cash numeric,p_notes text)
returns jsonb language plpgsql security definer set search_path to pg_catalog,public,auth,extensions
as $$ declare v_shift public.cashier_shifts%rowtype;v_cash_pay numeric:=0;v_in numeric:=0;v_out numeric:=0;v_refund numeric:=0;v_expected numeric;
begin
 if not public.has_business_role(p_bid,array['owner','admin','cashier']) then return jsonb_build_object('ok',false,'error','Tidak diizinkan');end if;
 select * into v_shift from public.cashier_shifts where id=p_shift_id and business_id=p_bid and status='open' for update;if not found then return jsonb_build_object('ok',false,'error','Shift tidak aktif');end if;
 select coalesce(sum(amount),0) into v_cash_pay from public.payments where business_id=p_bid and lower(method)='cash' and created_at>=v_shift.opened_at and created_at<=now();
 select coalesce(sum(case when type='in' then amount else 0 end),0),coalesce(sum(case when type='out' then amount else 0 end),0) into v_in,v_out from public.cash_movements where shift_id=p_shift_id;
 select coalesce(sum(amount),0) into v_refund from public.sale_adjustments where business_id=p_bid and lower(coalesce(payment_method,''))='cash' and created_at>=v_shift.opened_at and created_at<=now();
 v_expected:=v_shift.opening_cash+v_cash_pay+v_in-v_out-v_refund;
 update public.cashier_shifts set status='closed',closed_at=now(),expected_cash=v_expected,closing_cash=greatest(coalesce(p_closing_cash,0),0),difference=greatest(coalesce(p_closing_cash,0),0)-v_expected,notes=p_notes where id=p_shift_id;
 return jsonb_build_object('ok',true,'expected_cash',v_expected,'difference',greatest(coalesce(p_closing_cash,0),0)-v_expected);
end $$;
revoke all on function public.close_cashier_shift_v116(uuid,uuid,numeric,text) from public,anon;grant execute on function public.close_cashier_shift_v116(uuid,uuid,numeric,text) to authenticated;

-- =========================================================
-- V1.12 / V1.15 RPCs
-- =========================================================
create or replace function public.apply_stock_opname_v116(p_bid uuid,p_product_id uuid,p_counted_stock numeric,p_reason text)
returns jsonb language plpgsql security definer set search_path to pg_catalog,public,auth,extensions
as $$ declare p public.products%rowtype;v_before numeric;v_counted numeric:=greatest(coalesce(p_counted_stock,0),0);
begin
 if not public.has_business_role(p_bid,array['owner','admin','warehouse']) then return jsonb_build_object('ok',false,'error','Tidak diizinkan');end if;
 select * into p from public.products where id=p_product_id and business_id=p_bid for update;if not found then return jsonb_build_object('ok',false,'error','Produk tidak ditemukan');end if;
 if coalesce(p.inventory_mode,'self')<>'self' or p.category='Jasa' then return jsonb_build_object('ok',false,'error','Opname hanya untuk produk dengan Stok Sendiri');end if;
 v_before:=coalesce(p.stock,0);update public.products set stock=v_counted,updated_at=now() where id=p.id;
 insert into public.stock_adjustments(business_id,product_id,before_stock,counted_stock,delta,reason,created_by) values(p_bid,p.id,v_before,v_counted,v_counted-v_before,coalesce(nullif(p_reason,''),'Stock opname'),auth.uid());
 return jsonb_build_object('ok',true,'before_stock',v_before,'counted_stock',v_counted,'delta',v_counted-v_before);
end $$;
revoke all on function public.apply_stock_opname_v116(uuid,uuid,numeric,text) from public,anon;grant execute on function public.apply_stock_opname_v116(uuid,uuid,numeric,text) to authenticated;

create or replace function public.save_product_recipe_v116(p_bid uuid,p_product_id uuid,p_items jsonb)
returns jsonb language plpgsql security definer set search_path to pg_catalog,public,auth,extensions
as $$ declare r jsonb;v_ing uuid;v_qty numeric;
begin
 if not public.has_business_role(p_bid,array['owner','admin','warehouse']) then return jsonb_build_object('ok',false,'error','Tidak diizinkan');end if;
 if not exists(select 1 from public.products where id=p_product_id and business_id=p_bid) then return jsonb_build_object('ok',false,'error','Produk tidak ditemukan');end if;
 if p_items is null or jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 then return jsonb_build_object('ok',false,'error','Minimal satu bahan baku');end if;
 delete from public.product_recipes where business_id=p_bid and product_id=p_product_id;
 for r in select * from jsonb_array_elements(p_items) loop
   v_ing:=(r->>'ingredient_product_id')::uuid;v_qty:=(r->>'qty_per_unit')::numeric;
   if v_ing=p_product_id or v_qty<=0 or not exists(select 1 from public.products where id=v_ing and business_id=p_bid) then raise exception 'Bahan baku recipe tidak valid';end if;
   insert into public.product_recipes(business_id,product_id,ingredient_product_id,qty_per_unit) values(p_bid,p_product_id,v_ing,v_qty);
 end loop;
 update public.products set inventory_mode='recipe',updated_at=now() where id=p_product_id and business_id=p_bid;
 return jsonb_build_object('ok',true);
end $$;
revoke all on function public.save_product_recipe_v116(uuid,uuid,jsonb) from public,anon;grant execute on function public.save_product_recipe_v116(uuid,uuid,jsonb) to authenticated;

-- =========================================================
-- V1.14 + V1.16 CREATE SALE RPC
-- =========================================================
create or replace function public.create_sale_v116(
 p_bid uuid,p_sale_date date,p_customer_id uuid,p_customer_name text,p_customer_phone text,p_customer_address text,p_sale_notes text,
 p_items jsonb,p_promo_name text,p_promo_discount numeric,p_service_rate numeric,p_tax_rate numeric,p_redeem_points integer,
 p_payment_method text,p_initial_paid numeric,p_shift_id uuid,p_request_id uuid default null
) returns jsonb language plpgsql security definer
set search_path to pg_catalog,public,auth,extensions
as $$
declare
 v_role text;v_request uuid:=coalesce(p_request_id,gen_random_uuid());v_existing public.sales%rowtype;v_sale public.sales%rowtype;v_payment public.payments%rowtype;
 v_inv text;v_sj text;v_kwt text;v_count int;v_matched int;v_total_qty numeric;v_subtotal numeric;v_cost numeric;v_first uuid;v_first_name text;v_first_price numeric;v_first_cost numeric;
 v_promo numeric;v_service_rate numeric;v_service numeric;v_tax_rate numeric;v_tax numeric;v_loyalty numeric:=0;v_total numeric;v_gp numeric;v_point_value numeric;v_spend_per_point numeric;v_redeem int:=0;v_earned int:=0;v_customer public.customers%rowtype;v_item record;
begin
 v_role:=public.business_role(p_bid);if v_role not in('owner','admin','cashier') then raise exception 'Role tidak boleh membuat penjualan';end if;
 if not exists(select 1 from public.cashier_shifts where id=p_shift_id and business_id=p_bid and status='open') then raise exception 'Buka Shift Kasir terlebih dahulu';end if;
 if p_items is null or jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 then raise exception 'Minimal satu item diperlukan';end if;
 select * into v_existing from public.sales where business_id=p_bid and client_request_id=v_request limit 1;if v_existing.id is not null then return jsonb_build_object('ok',true,'duplicate',true,'sale_id',v_existing.id,'invoice_no',v_existing.invoice_no);end if;
 perform 1 from public.products p where p.id in(select (e.value->>'product_id')::uuid from jsonb_array_elements(p_items)e(value)) order by p.id for update;
 select count(*),count(p.id),sum((e.value->>'qty')::numeric),sum((e.value->>'qty')::numeric*p.price),sum((e.value->>'qty')::numeric*public.product_unit_cost_v116(p_bid,p.id))
 into v_count,v_matched,v_total_qty,v_subtotal,v_cost from jsonb_array_elements(p_items)e(value) left join public.products p on p.id=(e.value->>'product_id')::uuid and p.business_id=p_bid;
 if v_count<>v_matched or exists(select 1 from jsonb_array_elements(p_items)e(value) where coalesce((e.value->>'qty')::numeric,0)<=0) then raise exception 'Item transaksi tidak valid';end if;
 select p.id,case when coalesce(p.variant_name,'')<>'' then p.name||' · '||p.variant_name else p.name end,p.price,public.product_unit_cost_v116(p_bid,p.id) into v_first,v_first_name,v_first_price,v_first_cost from jsonb_array_elements(p_items) with ordinality e(value,ord) join public.products p on p.id=(e.value->>'product_id')::uuid where p.business_id=p_bid order by e.ord limit 1;
 v_promo:=least(greatest(coalesce(p_promo_discount,0),0),coalesce(v_subtotal,0));v_service_rate:=least(greatest(coalesce(p_service_rate,0),0),100);v_service:=(v_subtotal-v_promo)*v_service_rate/100;v_tax_rate:=least(greatest(coalesce(p_tax_rate,0),0),100);v_tax:=(v_subtotal-v_promo+v_service)*v_tax_rate/100;
 select greatest(coalesce(loyalty_point_value,100),0),greatest(coalesce(loyalty_spend_per_point,10000),1) into v_point_value,v_spend_per_point from public.businesses where id=p_bid;
 if p_customer_id is not null then select * into v_customer from public.customers where id=p_customer_id and business_id=p_bid and active=true for update;if not found then raise exception 'Member tidak ditemukan';end if;v_redeem:=least(greatest(coalesce(p_redeem_points,0),0),coalesce(v_customer.points_balance,0));v_loyalty:=least((v_subtotal-v_promo+v_service+v_tax),v_redeem*v_point_value);end if;
 v_total:=greatest(v_subtotal-v_promo+v_service+v_tax-v_loyalty,0);v_gp:=(v_subtotal-v_promo+v_service-v_loyalty)-v_cost;if coalesce(p_initial_paid,0)>v_total+0.005 then raise exception 'Pembayaran awal melebihi total';end if;
 v_inv:=public.next_document_number(p_bid,'INV',coalesce(p_sale_date,current_date));v_sj:=public.next_document_number(p_bid,'SJ',coalesce(p_sale_date,current_date));
 insert into public.sales(business_id,date,invoice_no,delivery_no,customer,customer_phone,customer_address,notes,product_id,product_name,qty,unit_price,unit_cost,discount,total,gross_profit,payment_method,paid_amount,client_request_id,subtotal,promo_name,promo_discount,loyalty_discount,service_rate,service_amount,tax_rate,tax_amount,status,customer_id,points_redeemed,cashier_shift_id)
 values(p_bid,coalesce(p_sale_date,current_date),v_inv,v_sj,coalesce(p_customer_name,v_customer.name),coalesce(p_customer_phone,v_customer.phone),coalesce(p_customer_address,v_customer.address),p_sale_notes,v_first,case when v_count=1 then v_first_name else v_first_name||' +'||(v_count-1)::text||' item' end,v_total_qty,v_first_price,v_first_cost,v_promo+v_loyalty,v_total,v_gp,coalesce(nullif(p_payment_method,''),'Cash'),0,v_request,v_subtotal,p_promo_name,v_promo,v_loyalty,v_service_rate,v_service,v_tax_rate,v_tax,'completed',p_customer_id,v_redeem,p_shift_id) returning * into v_sale;
 for v_item in select e.value,e.ord from jsonb_array_elements(p_items) with ordinality e(value,ord) order by e.ord loop insert into public.sale_items(business_id,sale_id,line_no,product_id,product_name,unit,qty,unit_price,unit_cost,line_total,line_gross_profit) values(p_bid,v_sale.id,v_item.ord,(v_item.value->>'product_id')::uuid,'','pcs',(v_item.value->>'qty')::numeric,0,0,0,0);end loop;
 if coalesce(p_initial_paid,0)>0 then v_kwt:=public.next_document_number(p_bid,'KWT',coalesce(p_sale_date,current_date));insert into public.payments(business_id,sale_id,payment_no,payment_date,amount,method,notes,receipt_no,client_request_id,created_by) values(p_bid,v_sale.id,0,coalesce(p_sale_date,current_date),p_initial_paid,coalesce(nullif(p_payment_method,''),'Cash'),'Pembayaran awal',v_kwt,v_request,auth.uid()) returning * into v_payment;end if;
 if p_customer_id is not null then
   v_earned:=floor(v_total/v_spend_per_point)::int;update public.customers set points_balance=greatest(points_balance-v_redeem,0)+v_earned,total_spend=total_spend+v_total,visit_count=visit_count+1,last_visit=coalesce(p_sale_date,current_date),updated_at=now() where id=p_customer_id;
   if v_redeem>0 then insert into public.loyalty_ledger(business_id,customer_id,sale_id,points,type,notes) values(p_bid,p_customer_id,v_sale.id,-v_redeem,'redeem','Tukar point '||v_inv);end if;
   if v_earned>0 then insert into public.loyalty_ledger(business_id,customer_id,sale_id,points,type,notes) values(p_bid,p_customer_id,v_sale.id,v_earned,'earn','Belanja '||v_inv);end if;
   update public.sales set points_earned=v_earned where id=v_sale.id;
 end if;
 return jsonb_build_object('ok',true,'sale_id',v_sale.id,'invoice_no',v_inv,'delivery_no',v_sj,'payment_id',v_payment.id,'points_earned',v_earned);
end $$;
revoke all on function public.create_sale_v116(uuid,date,uuid,text,text,text,text,jsonb,text,numeric,numeric,numeric,integer,text,numeric,uuid,uuid) from public,anon;
grant execute on function public.create_sale_v116(uuid,date,uuid,text,text,text,text,jsonb,text,numeric,numeric,numeric,integer,text,numeric,uuid,uuid) to authenticated;

-- =========================================================
-- V1.11 REFUND / VOID RPC
-- =========================================================
create or replace function public.process_sale_adjustment_v116(p_bid uuid,p_sale_id uuid,p_type text,p_items jsonb,p_reason text,p_payment_method text)
returns jsonb language plpgsql security definer set search_path to pg_catalog,public,auth,extensions
as $$
declare s public.sales%rowtype;r jsonb;si public.sale_items%rowtype;v_q numeric;v_returned numeric;v_raw numeric:=0;v_cost numeric:=0;v_amount numeric;v_remaining numeric;v_rows jsonb:='[]'::jsonb;v_reverse int:=0;v_spend numeric;
begin
 if not public.has_business_role(p_bid,array['owner','admin']) then return jsonb_build_object('ok',false,'error','Hanya Owner/Admin yang dapat refund atau void');end if;
 if p_type not in('refund','void') then return jsonb_build_object('ok',false,'error','Jenis adjustment tidak valid');end if;
 select * into s from public.sales where id=p_sale_id and business_id=p_bid for update;if not found then return jsonb_build_object('ok',false,'error','Transaksi tidak ditemukan');end if;
 if s.status in('void','refunded') then return jsonb_build_object('ok',false,'error','Transaksi sudah ditutup');end if;if p_type='void' and coalesce(s.refund_total,0)>0 then return jsonb_build_object('ok',false,'error','Transaksi yang sudah refund sebagian tidak dapat di-void; lakukan refund sisa');end if;
 for r in select * from jsonb_array_elements(coalesce(p_items,'[]'::jsonb)) loop
   select * into si from public.sale_items where id=(r->>'sale_item_id')::uuid and sale_id=p_sale_id and business_id=p_bid for update;if not found then continue;end if;
   select coalesce(sum((e->>'qty')::numeric),0) into v_returned from public.sale_adjustments a cross join lateral jsonb_array_elements(a.items)e where a.business_id=p_bid and a.sale_id=p_sale_id and e->>'sale_item_id'=si.id::text;
   v_q:=least(greatest(coalesce((r->>'qty')::numeric,0),0),greatest(si.qty-v_returned,0));if v_q<=0 then continue;end if;
   v_raw:=v_raw+v_q*si.unit_price;v_cost:=v_cost+v_q*si.unit_cost;perform public.adjust_product_inventory_v116(p_bid,si.product_id,v_q);
   v_rows:=v_rows||jsonb_build_array(jsonb_build_object('sale_item_id',si.id,'product_id',si.product_id,'qty',v_q,'amount',v_q*si.unit_price,'cost',v_q*si.unit_cost));
 end loop;
 if jsonb_array_length(v_rows)=0 then return jsonb_build_object('ok',false,'error','Tidak ada qty refund yang valid');end if;
 v_remaining:=greatest(s.total-coalesce(s.refund_total,0),0);v_amount:=case when p_type='void' then v_remaining else least(v_remaining,v_raw/greatest(coalesce(s.subtotal,s.total+s.discount),1)*s.total) end;
 insert into public.sale_adjustments(business_id,sale_id,type,date,amount,cost_amount,payment_method,reason,items,created_by) values(p_bid,p_sale_id,p_type,current_date,v_amount,v_cost,p_payment_method,p_reason,v_rows,auth.uid());
 update public.sales set refund_total=coalesce(refund_total,0)+v_amount,refund_cost=coalesce(refund_cost,0)+v_cost,status=case when p_type='void' then 'void' when greatest(total-(coalesce(refund_total,0)+v_amount),0)<=0.01 then 'refunded' else 'partial_refund' end,updated_at=now() where id=p_sale_id;
 if s.customer_id is not null then
   select greatest(coalesce(loyalty_spend_per_point,10000),1) into v_spend from public.businesses where id=p_bid;v_reverse:=floor(v_amount/v_spend)::int;
   update public.customers set total_spend=greatest(total_spend-v_amount,0),points_balance=greatest(points_balance-v_reverse,0),updated_at=now() where id=s.customer_id;
   if v_reverse>0 then insert into public.loyalty_ledger(business_id,customer_id,sale_id,points,type,notes) values(p_bid,s.customer_id,s.id,-v_reverse,'refund','Refund '||s.invoice_no);end if;
 end if;
 return jsonb_build_object('ok',true,'amount',v_amount,'status',case when p_type='void' then 'void' when greatest(s.total-(coalesce(s.refund_total,0)+v_amount),0)<=0.01 then 'refunded' else 'partial_refund' end);
end $$;
revoke all on function public.process_sale_adjustment_v116(uuid,uuid,text,jsonb,text,text) from public,anon;grant execute on function public.process_sale_adjustment_v116(uuid,uuid,text,jsonb,text,text) to authenticated;

-- =========================================================
-- V1.16 ROLE HARDENING FOR PURCHASING
-- Warehouse can receive goods but must not receive purchase price / payable values.
-- =========================================================
drop policy if exists "po view" on public.purchase_orders;
drop policy if exists "po view financial v116" on public.purchase_orders;
create policy "po view financial v116" on public.purchase_orders for select to authenticated
  using(public.has_business_role(business_id,array['owner','admin','finance']));
drop policy if exists "po items view" on public.purchase_order_items;
drop policy if exists "po items view financial v116" on public.purchase_order_items;
create policy "po items view financial v116" on public.purchase_order_items for select to authenticated
  using(public.has_business_role(business_id,array['owner','admin','finance']));

create or replace function public.list_purchase_orders_for_business_v116(p_bid uuid)
returns table(
  id uuid,business_id uuid,po_no text,supplier_id uuid,order_date date,notes text,
  total_amount numeric,paid_amount numeric,status text,created_at timestamptz,updated_at timestamptz
)
language plpgsql security definer stable set search_path to pg_catalog,public,auth,extensions
as $$
declare r text;
begin
  r:=public.business_role(p_bid);
  if r not in('owner','admin','finance','warehouse') then raise exception 'Tidak memiliki akses pembelian'; end if;
  return query
  select p.id,p.business_id,p.po_no,p.supplier_id,p.order_date,
         case when r='warehouse' then null else p.notes end,
         case when r='warehouse' then null else p.total_amount end,
         case when r='warehouse' then null else p.paid_amount end,
         p.status,p.created_at,p.updated_at
  from public.purchase_orders p where p.business_id=p_bid
  order by p.order_date desc,p.created_at desc;
end $$;
revoke all on function public.list_purchase_orders_for_business_v116(uuid) from public,anon;
grant execute on function public.list_purchase_orders_for_business_v116(uuid) to authenticated;

create or replace function public.list_purchase_order_items_for_business_v116(p_bid uuid)
returns table(
  id uuid,business_id uuid,purchase_order_id uuid,line_no integer,product_id uuid,product_name text,unit text,
  qty numeric,unit_cost numeric,line_total numeric,received_qty numeric,created_at timestamptz
)
language plpgsql security definer stable set search_path to pg_catalog,public,auth,extensions
as $$
declare r text;
begin
  r:=public.business_role(p_bid);
  if r not in('owner','admin','finance','warehouse') then raise exception 'Tidak memiliki akses item pembelian'; end if;
  return query
  select i.id,i.business_id,i.purchase_order_id,i.line_no,i.product_id,i.product_name,i.unit,i.qty,
         case when r='warehouse' then null else i.unit_cost end,
         case when r='warehouse' then null else i.line_total end,
         i.received_qty,i.created_at
  from public.purchase_order_items i where i.business_id=p_bid
  order by i.purchase_order_id,i.line_no;
end $$;
revoke all on function public.list_purchase_order_items_for_business_v116(uuid) from public,anon;
grant execute on function public.list_purchase_order_items_for_business_v116(uuid) to authenticated;

-- =========================================================
-- Role-safe read RPCs with V1.16 columns
-- =========================================================
drop function if exists public.list_products_for_business(uuid);
create function public.list_products_for_business(p_bid uuid)
returns table(id uuid,business_id uuid,sku text,name text,category text,unit text,cost numeric,price numeric,stock numeric,min_stock numeric,created_at timestamptz,updated_at timestamptz,client_request_id uuid,barcode text,variant_name text,inventory_mode text)
language plpgsql security definer stable set search_path to pg_catalog,public,auth,extensions
as $$ declare v_role text;begin v_role:=public.business_role(p_bid);if v_role='none' then raise exception 'Tidak memiliki akses bisnis';end if;return query select p.id,p.business_id,p.sku,p.name,p.category,p.unit,case when v_role in('owner','admin','finance') then p.cost else null end,case when v_role='warehouse' then null else p.price end,p.stock,p.min_stock,p.created_at,p.updated_at,p.client_request_id,p.barcode,p.variant_name,p.inventory_mode from public.products p where p.business_id=p_bid order by p.created_at asc;end $$;
revoke all on function public.list_products_for_business(uuid) from public,anon;grant execute on function public.list_products_for_business(uuid) to authenticated;

drop function if exists public.list_sales_for_business(uuid);
create function public.list_sales_for_business(bid uuid)
returns table(id uuid,business_id uuid,date date,invoice_no text,delivery_no text,customer text,customer_phone text,customer_address text,notes text,product_id uuid,product_name text,qty numeric,unit_price numeric,unit_cost numeric,discount numeric,total numeric,gross_profit numeric,payment_method text,paid_amount numeric,created_at timestamptz,updated_at timestamptz,client_request_id uuid,subtotal numeric,promo_name text,promo_discount numeric,loyalty_discount numeric,service_rate numeric,service_amount numeric,tax_rate numeric,tax_amount numeric,refund_total numeric,refund_cost numeric,status text,customer_id uuid,points_earned integer,points_redeemed integer,cashier_shift_id uuid)
language plpgsql security definer stable set search_path to pg_catalog,public,auth,extensions
as $$ declare r text;begin r:=public.business_role(bid);if r not in('owner','admin','cashier','finance','warehouse') then raise exception 'Tidak memiliki akses penjualan';end if;return query select s.id,s.business_id,s.date,s.invoice_no,s.delivery_no,s.customer,s.customer_phone,s.customer_address,s.notes,s.product_id,s.product_name,s.qty,case when r='warehouse' then null else s.unit_price end,case when r in('owner','admin','finance') then s.unit_cost else null end,case when r='warehouse' then null else s.discount end,case when r='warehouse' then null else s.total end,case when r in('owner','admin','finance') then s.gross_profit else null end,case when r='warehouse' then null else s.payment_method end,case when r='warehouse' then null else s.paid_amount end,s.created_at,s.updated_at,s.client_request_id,case when r='warehouse' then null else s.subtotal end,s.promo_name,case when r='warehouse' then null else s.promo_discount end,case when r='warehouse' then null else s.loyalty_discount end,s.service_rate,case when r='warehouse' then null else s.service_amount end,s.tax_rate,case when r='warehouse' then null else s.tax_amount end,case when r='warehouse' then null else s.refund_total end,case when r in('owner','admin','finance') then s.refund_cost else null end,s.status,s.customer_id,s.points_earned,s.points_redeemed,s.cashier_shift_id from public.sales s where s.business_id=bid order by s.date desc,s.created_at desc;end $$;
revoke all on function public.list_sales_for_business(uuid) from public,anon;grant execute on function public.list_sales_for_business(uuid) to authenticated;

-- New functions/tables should not be callable by anon.
revoke all on function public.customer_member_no_v116() from public,anon,authenticated;

-- V1.16 warehouse product master-field hardening
-- Extend the active V1.8 product guard so Gudang remains stock/min-stock only.
create or replace function public.guard_product_update_v18()
returns trigger
language plpgsql
security definer
set search_path to pg_catalog, public, auth, extensions
as $$
begin
  if new.id is distinct from old.id
     or new.business_id is distinct from old.business_id
     or new.created_at is distinct from old.created_at
     or new.client_request_id is distinct from old.client_request_id then
    raise exception 'Field sistem produk tidak boleh diubah';
  end if;

  if public.business_role(old.business_id)='warehouse' then
    if new.sku is distinct from old.sku
       or new.barcode is distinct from old.barcode
       or new.name is distinct from old.name
       or new.variant_name is distinct from old.variant_name
       or new.category is distinct from old.category
       or new.unit is distinct from old.unit
       or new.inventory_mode is distinct from old.inventory_mode
       or new.cost is distinct from old.cost
       or new.price is distinct from old.price then
      raise exception 'Role Gudang hanya boleh mengubah stok dan minimum stok';
    end if;
  end if;

  new.updated_at:=now();
  return new;
end;
$$;

revoke all on function public.guard_product_update_v18() from public, anon, authenticated;

commit;
