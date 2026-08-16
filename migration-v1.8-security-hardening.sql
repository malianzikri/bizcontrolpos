-- BizControl Online V1.8 — Security Hardening
-- Apply AFTER V1.7 / V1.7.1 schema.
-- Main changes: immutable system fields, least-privilege grants, atomic sales/payments,
-- Security Key lockout, warehouse financial masking, and stock-negative protection.

begin;

create extension if not exists pgcrypto;

-- =========================================================
-- 1. Business controls & Security Key attempt tracking
-- =========================================================
alter table public.businesses
  add column if not exists allow_negative_stock boolean not null default false;

create table if not exists public.security_key_attempts(
  business_id uuid not null references public.businesses(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  failed_attempts integer not null default 0 check(failed_attempts >= 0),
  locked_until timestamptz,
  last_failed_at timestamptz,
  updated_at timestamptz not null default now(),
  primary key(business_id,user_id)
);
alter table public.security_key_attempts enable row level security;
revoke all on public.security_key_attempts from public,anon,authenticated;

-- System identity of a business must never be editable through the client.
create or replace function public.guard_business_identity()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
begin
  if new.id is distinct from old.id
     or new.owner_id is distinct from old.owner_id
     or new.created_at is distinct from old.created_at then
    raise exception 'Field sistem bisnis tidak boleh diubah';
  end if;
  new.updated_at:=now();
  return new;
end;
$$;
revoke all on function public.guard_business_identity() from public;
drop trigger if exists trg_guard_business_identity on public.businesses;
create trigger trg_guard_business_identity
before update on public.businesses
for each row execute function public.guard_business_identity();

-- Product identity is immutable. Warehouse remains stock-only.
create or replace function public.guard_product_update_v18()
returns trigger
language plpgsql
security definer
set search_path=public
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
       or new.name is distinct from old.name
       or new.category is distinct from old.category
       or new.unit is distinct from old.unit
       or new.cost is distinct from old.cost
       or new.price is distinct from old.price then
      raise exception 'Role Gudang hanya boleh mengubah stok dan minimum stok';
    end if;
  end if;

  new.updated_at:=now();
  return new;
end;
$$;
revoke all on function public.guard_product_update_v18() from public;
drop trigger if exists trg_guard_warehouse_product_update on public.products;
drop trigger if exists trg_guard_product_update_v18 on public.products;
create trigger trg_guard_product_update_v18
before update on public.products
for each row execute function public.guard_product_update_v18();

create or replace function public.guard_expense_update_v18()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
begin
  if new.id is distinct from old.id
     or new.business_id is distinct from old.business_id
     or new.created_at is distinct from old.created_at
     or new.client_request_id is distinct from old.client_request_id then
    raise exception 'Field sistem biaya tidak boleh diubah';
  end if;
  new.updated_at:=now();
  return new;
end;
$$;
revoke all on function public.guard_expense_update_v18() from public;
drop trigger if exists trg_guard_expense_update_v18 on public.expenses;
create trigger trg_guard_expense_update_v18
before update on public.expenses
for each row execute function public.guard_expense_update_v18();

create or replace function public.guard_member_identity_v18()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
begin
  if new.id is distinct from old.id
     or new.business_id is distinct from old.business_id
     or new.user_id is distinct from old.user_id
     or new.created_at is distinct from old.created_at then
    raise exception 'Identitas anggota tidak boleh diubah';
  end if;
  return new;
end;
$$;
revoke all on function public.guard_member_identity_v18() from public;
drop trigger if exists trg_guard_member_identity_v18 on public.business_members;
create trigger trg_guard_member_identity_v18
before update on public.business_members
for each row execute function public.guard_member_identity_v18();

-- =========================================================
-- 2. Role-safe reads: warehouse sees fulfilment data only
-- =========================================================
-- Products are role-safe too: warehouse does not receive HPP or selling price.
drop function if exists public.list_products_for_business(uuid);

create or replace function public.list_products_for_business(p_bid uuid)
returns table(
  id uuid,business_id uuid,sku text,name text,category text,unit text,cost numeric,price numeric,
  stock numeric,min_stock numeric,created_at timestamptz,updated_at timestamptz,client_request_id uuid
)
language plpgsql
security definer
set search_path=public
stable
as $$
declare v_role text;
begin
  v_role:=public.business_role(p_bid);
  if v_role='none' then raise exception 'Tidak memiliki akses bisnis'; end if;
  return query
    select p.id,p.business_id,p.sku,p.name,p.category,p.unit,
           case when v_role in ('owner','admin','finance') then p.cost else null end,
           case when v_role='warehouse' then null else p.price end,
           p.stock,p.min_stock,p.created_at,p.updated_at,p.client_request_id
    from public.products p where p.business_id=p_bid order by p.created_at asc;
end;
$$;
revoke all on function public.list_products_for_business(uuid) from public,anon;
grant execute on function public.list_products_for_business(uuid) to authenticated;

create or replace function public.list_sales_for_business(bid uuid)
returns table(
  id uuid,business_id uuid,date date,invoice_no text,delivery_no text,customer text,customer_phone text,
  customer_address text,notes text,product_id uuid,product_name text,qty numeric,unit_price numeric,
  unit_cost numeric,discount numeric,total numeric,gross_profit numeric,payment_method text,paid_amount numeric,
  created_at timestamptz,updated_at timestamptz,client_request_id uuid
)
language plpgsql
security definer
set search_path=public
stable
as $$
declare r text;
begin
  r:=public.business_role(bid);
  if r not in ('owner','admin','cashier','finance','warehouse') then
    raise exception 'Tidak memiliki akses penjualan';
  end if;

  return query
    select s.id,s.business_id,s.date,s.invoice_no,s.delivery_no,s.customer,s.customer_phone,s.customer_address,
           s.notes,s.product_id,s.product_name,s.qty,
           case when r='warehouse' then null else s.unit_price end,
           case when r in ('owner','admin','finance') then s.unit_cost else null end,
           case when r='warehouse' then null else s.discount end,
           case when r='warehouse' then null else s.total end,
           case when r in ('owner','admin','finance') then s.gross_profit else null end,
           case when r='warehouse' then null else s.payment_method end,
           case when r='warehouse' then null else s.paid_amount end,
           s.created_at,s.updated_at,s.client_request_id
    from public.sales s
    where s.business_id=bid
    order by s.date desc,s.created_at desc;
end;
$$;
revoke all on function public.list_sales_for_business(uuid) from public,anon;
grant execute on function public.list_sales_for_business(uuid) to authenticated;

-- =========================================================
-- 3. Server-owned sale calculations + stock locking
-- =========================================================
create or replace function public.prepare_sale_financials()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare
  p_name text;
  p_cost numeric;
  p_price numeric;
  p_business uuid;
  p_category text;
  p_stock numeric;
  allow_negative boolean:=false;
  available numeric;
begin
  if new.qty is null or new.qty<=0 then raise exception 'Qty harus lebih dari 0'; end if;

  if tg_op='UPDATE' then
    if new.id is distinct from old.id
       or new.business_id is distinct from old.business_id
       or new.created_at is distinct from old.created_at
       or new.client_request_id is distinct from old.client_request_id then
      raise exception 'Field sistem transaksi tidak boleh diubah';
    end if;
    new.invoice_no:=old.invoice_no;
    new.delivery_no:=old.delivery_no;
    if new.paid_amount is distinct from old.paid_amount and pg_trigger_depth()<=1 then
      raise exception 'Jumlah dibayar hanya boleh berubah melalui Riwayat Pembayaran';
    end if;

    -- Lock old/new product rows in deterministic UUID order to reduce race/deadlock risk.
    perform 1 from public.products
      where id in (old.product_id,new.product_id)
      order by id
      for update;
  else
    perform 1 from public.products where id=new.product_id for update;
  end if;

  select p.name,p.cost,p.price,p.business_id,p.category,p.stock
    into p_name,p_cost,p_price,p_business,p_category,p_stock
  from public.products p where p.id=new.product_id;

  if p_business is null then raise exception 'Produk tidak ditemukan'; end if;
  if p_business<>new.business_id then raise exception 'Produk dan transaksi harus berada pada bisnis yang sama'; end if;

  select b.allow_negative_stock into allow_negative from public.businesses b where b.id=new.business_id;
  allow_negative:=coalesce(allow_negative,false);

  if p_category<>'Jasa' and not allow_negative then
    available:=coalesce(p_stock,0);
    if tg_op='UPDATE' and old.product_id=new.product_id then
      available:=available+coalesce(old.qty,0);
    end if;
    if new.qty>available then
      raise exception 'Stok tidak cukup. Tersedia: %',available;
    end if;
  end if;

  if tg_op='INSERT' then
    new.product_name:=p_name;
    new.unit_cost:=p_cost;
    new.unit_price:=p_price;
    new.paid_amount:=0;
  elsif new.product_id is distinct from old.product_id then
    new.product_name:=p_name;
    new.unit_cost:=p_cost;
    new.unit_price:=p_price;
  else
    new.product_name:=old.product_name;
    new.unit_cost:=old.unit_cost;
    new.unit_price:=old.unit_price;
  end if;

  new.discount:=greatest(coalesce(new.discount,0),0);
  new.total:=greatest(new.qty*new.unit_price-new.discount,0);
  new.gross_profit:=new.total-(new.qty*new.unit_cost);
  if tg_op='UPDATE' and coalesce(old.paid_amount,0)>new.total+0.005 then
    raise exception 'Total transaksi baru lebih kecil dari pembayaran yang sudah tercatat';
  end if;
  new.updated_at:=now();
  return new;
end;
$$;
revoke all on function public.prepare_sale_financials() from public,anon,authenticated;
drop trigger if exists trg_prepare_sale_financials on public.sales;
create trigger trg_prepare_sale_financials
before insert or update on public.sales
for each row execute function public.prepare_sale_financials();

-- Payment trigger also locks its parent invoice. This serializes concurrent payment writes.
create or replace function public.prepare_payment()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare
  sale_total numeric(18,2);
  sale_business uuid;
  other_paid numeric(18,2);
begin
  if tg_op='UPDATE' then
    if new.id is distinct from old.id
       or new.business_id is distinct from old.business_id
       or new.sale_id is distinct from old.sale_id
       or new.payment_no is distinct from old.payment_no
       or new.receipt_no is distinct from old.receipt_no
       or new.client_request_id is distinct from old.client_request_id
       or new.created_at is distinct from old.created_at
       or new.created_by is distinct from old.created_by then
      raise exception 'Field sistem pembayaran tidak boleh diubah';
    end if;
  end if;

  select s.total,s.business_id into sale_total,sale_business
    from public.sales s where s.id=new.sale_id for update;
  if sale_total is null then raise exception 'Invoice tidak ditemukan'; end if;
  if new.business_id<>sale_business then raise exception 'Pembayaran dan invoice harus berada pada bisnis yang sama'; end if;
  if new.amount is null or new.amount<=0 then raise exception 'Jumlah pembayaran harus lebih dari 0'; end if;

  if tg_op='INSERT' and coalesce(new.payment_no,0)<=0 then
    select coalesce(max(p.payment_no),0)+1 into new.payment_no from public.payments p where p.sale_id=new.sale_id;
  end if;

  select coalesce(sum(p.amount),0) into other_paid
  from public.payments p
  where p.sale_id=new.sale_id and (tg_op='INSERT' or p.id<>new.id);

  if other_paid+new.amount>sale_total+0.005 then raise exception 'Pembayaran melebihi sisa tagihan'; end if;
  new.updated_at:=now();
  if new.created_by is null then new.created_by:=auth.uid(); end if;
  return new;
end;
$$;
revoke all on function public.prepare_payment() from public,anon,authenticated;
drop trigger if exists trg_prepare_payment on public.payments;
create trigger trg_prepare_payment
before insert or update on public.payments
for each row execute function public.prepare_payment();

-- =========================================================
-- 4. Atomic sale + initial payment RPC
-- =========================================================
create or replace function public.create_sale_with_payment(
  p_bid uuid,
  p_sale_date date,
  p_customer_name text,
  p_customer_phone text,
  p_customer_address text,
  p_sale_notes text,
  p_product_id uuid,
  p_qty numeric,
  p_discount numeric,
  p_payment_method text,
  p_initial_paid numeric default 0,
  p_request_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_role text;
  v_inv text;
  v_sj text;
  v_kwt text;
  v_sale public.sales%rowtype;
  v_payment public.payments%rowtype;
  v_existing_id uuid;
  v_request_id uuid:=coalesce(p_request_id,gen_random_uuid());
begin
  v_role:=public.business_role(p_bid);
  if v_role not in ('owner','admin','cashier') then raise exception 'Role tidak boleh membuat penjualan'; end if;

  select x.id into v_existing_id from public.sales x
    where x.business_id=p_bid and x.client_request_id=v_request_id limit 1;
  if v_existing_id is not null then
    select * into v_sale from public.sales where id=v_existing_id;
    select * into v_payment from public.payments where sale_id=v_existing_id order by payment_no asc limit 1;
    return jsonb_build_object('ok',true,'duplicate',true,'sale',to_jsonb(v_sale),'payment',case when v_payment.id is null then null else to_jsonb(v_payment) end);
  end if;

  v_inv:=public.next_document_number(p_bid,'INV',coalesce(p_sale_date,current_date));
  v_sj:=public.next_document_number(p_bid,'SJ',coalesce(p_sale_date,current_date));

  insert into public.sales(
    business_id,date,invoice_no,delivery_no,customer,customer_phone,customer_address,notes,
    product_id,product_name,qty,unit_price,unit_cost,discount,total,gross_profit,payment_method,paid_amount,client_request_id
  ) values (
    p_bid,coalesce(p_sale_date,current_date),v_inv,v_sj,p_customer_name,p_customer_phone,p_customer_address,p_sale_notes,
    p_product_id,'',p_qty,0,0,coalesce(p_discount,0),0,0,coalesce(nullif(p_payment_method,''),'Cash'),0,v_request_id
  ) returning * into v_sale;

  if coalesce(p_initial_paid,0)>0 then
    if p_initial_paid>v_sale.total+0.005 then raise exception 'Pembayaran awal melebihi total invoice'; end if;
    v_kwt:=public.next_document_number(p_bid,'KWT',coalesce(p_sale_date,current_date));
    insert into public.payments(
      business_id,sale_id,payment_no,payment_date,amount,method,notes,receipt_no,client_request_id,created_by
    ) values (
      p_bid,v_sale.id,0,coalesce(p_sale_date,current_date),p_initial_paid,coalesce(nullif(p_payment_method,''),'Cash'),
      'Pembayaran awal',v_kwt,v_request_id,auth.uid()
    ) returning * into v_payment;
  end if;

  select * into v_sale from public.sales where id=v_sale.id;
  return jsonb_build_object('ok',true,'duplicate',false,'sale',to_jsonb(v_sale),'payment',case when v_payment.id is null then null else to_jsonb(v_payment) end);
end;
$$;
revoke all on function public.create_sale_with_payment(uuid,date,text,text,text,text,uuid,numeric,numeric,text,numeric,uuid) from public,anon;
grant execute on function public.create_sale_with_payment(uuid,date,text,text,text,text,uuid,numeric,numeric,text,numeric,uuid) to authenticated;

create or replace function public.update_sale_secure(
  p_bid uuid,
  p_sale_id uuid,
  p_sale_date date,
  p_customer_name text,
  p_customer_phone text,
  p_customer_address text,
  p_sale_notes text,
  p_product_id uuid,
  p_qty numeric,
  p_discount numeric,
  p_payment_method text
)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare v_role text; v_sale public.sales%rowtype;
begin
  v_role:=public.business_role(p_bid);
  if v_role not in ('owner','admin','cashier') then raise exception 'Role tidak boleh mengubah penjualan'; end if;
  if not exists(select 1 from public.sales x where x.id=p_sale_id and x.business_id=p_bid) then raise exception 'Transaksi tidak ditemukan'; end if;

  update public.sales s set
    date=coalesce(p_sale_date,s.date),
    customer=p_customer_name,
    customer_phone=p_customer_phone,
    customer_address=p_customer_address,
    notes=p_sale_notes,
    product_id=p_product_id,
    qty=p_qty,
    discount=coalesce(p_discount,0),
    payment_method=coalesce(nullif(p_payment_method,''),s.payment_method)
  where s.id=p_sale_id and s.business_id=p_bid
  returning s.* into v_sale;
  return jsonb_build_object('ok',true,'sale',to_jsonb(v_sale));
end;
$$;
revoke all on function public.update_sale_secure(uuid,uuid,date,text,text,text,text,uuid,numeric,numeric,text) from public,anon;
grant execute on function public.update_sale_secure(uuid,uuid,date,text,text,text,text,uuid,numeric,numeric,text) to authenticated;

-- =========================================================
-- 5. Atomic payment create/update RPC
-- =========================================================
create or replace function public.record_payment(
  p_bid uuid,
  p_sale_id uuid,
  p_payment_id uuid default null,
  p_payment_date date default current_date,
  p_amount numeric default 0,
  p_method text default 'Cash',
  p_notes text default null,
  p_request_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_role text;
  v_sale public.sales%rowtype;
  v_payment public.payments%rowtype;
  v_kwt text;
  v_existing_id uuid;
  v_request_id uuid:=coalesce(p_request_id,gen_random_uuid());
begin
  v_role:=public.business_role(p_bid);
  if v_role not in ('owner','admin','cashier','finance') then raise exception 'Role tidak boleh mengelola pembayaran'; end if;
  select * into v_sale from public.sales s where s.id=p_sale_id and s.business_id=p_bid for update;
  if v_sale.id is null then raise exception 'Invoice tidak ditemukan'; end if;
  if p_amount is null or p_amount<=0 then raise exception 'Jumlah pembayaran harus lebih dari 0'; end if;

  if p_payment_id is null then
    select x.id into v_existing_id from public.payments x
      where x.business_id=p_bid and x.client_request_id=v_request_id limit 1;
    if v_existing_id is not null then
      select * into v_payment from public.payments where id=v_existing_id;
      return jsonb_build_object('ok',true,'duplicate',true,'payment',to_jsonb(v_payment));
    end if;
    v_kwt:=public.next_document_number(p_bid,'KWT',coalesce(p_payment_date,current_date));
    insert into public.payments(business_id,sale_id,payment_no,payment_date,amount,method,notes,receipt_no,client_request_id,created_by)
    values(p_bid,p_sale_id,0,coalesce(p_payment_date,current_date),p_amount,coalesce(nullif(p_method,''),'Cash'),p_notes,v_kwt,v_request_id,auth.uid())
    returning * into v_payment;
  else
    if not exists(select 1 from public.payments x where x.id=p_payment_id and x.sale_id=p_sale_id and x.business_id=p_bid) then raise exception 'Pembayaran tidak ditemukan'; end if;
    update public.payments p set
      payment_date=coalesce(p_payment_date,p.payment_date),
      amount=p_amount,
      method=coalesce(nullif(p_method,''),p.method),
      notes=p_notes
    where p.id=p_payment_id and p.sale_id=p_sale_id and p.business_id=p_bid
    returning p.* into v_payment;
  end if;

  return jsonb_build_object('ok',true,'duplicate',false,'payment',to_jsonb(v_payment));
end;
$$;
revoke all on function public.record_payment(uuid,uuid,uuid,date,numeric,text,text,uuid) from public,anon;
grant execute on function public.record_payment(uuid,uuid,uuid,date,numeric,text,text,uuid) to authenticated;

-- =========================================================
-- 6. Rate-limited Security Key RPCs
-- =========================================================
create or replace function public.set_delete_pin_v2(p_bid uuid, p_new_pin text, p_current_pin text default null)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_stored_hash text;
  v_att public.security_key_attempts%rowtype;
  v_new_count integer;
  v_lock_until timestamptz;
begin
  if auth.uid() is null or public.business_role(p_bid)<>'owner' then raise exception 'Hanya owner yang dapat mengatur Security Key'; end if;
  if p_new_pin !~ '^[0-9]{6}$' then return jsonb_build_object('ok',false,'error','Security Key harus 6 digit'); end if;

  insert into public.security_key_attempts(business_id,user_id,failed_attempts,updated_at)
  values(p_bid,auth.uid(),0,now()) on conflict(business_id,user_id) do nothing;
  select * into v_att from public.security_key_attempts where business_id=p_bid and user_id=auth.uid() for update;
  if v_att.locked_until is not null and v_att.locked_until>now() then
    return jsonb_build_object('ok',false,'error','Security Key terkunci sementara','locked_until',v_att.locked_until);
  end if;

  select delete_pin_hash into v_stored_hash from public.business_security where business_id=p_bid;
  if v_stored_hash is not null then
    if p_current_pin is null or crypt(p_current_pin,v_stored_hash)<>v_stored_hash then
      v_new_count:=coalesce(v_att.failed_attempts,0)+1;
      v_lock_until:=case when v_new_count>=5 then now()+interval '15 minutes' else null end;
      update public.security_key_attempts set failed_attempts=case when v_new_count>=5 then 0 else v_new_count end,
        locked_until=v_lock_until,last_failed_at=now(),updated_at=now()
      where business_id=p_bid and user_id=auth.uid();
      return jsonb_build_object('ok',false,
        'error',case when v_lock_until is not null then 'Terlalu banyak percobaan. Security Key dikunci 15 menit.' else 'Security Key saat ini salah' end,
        'remaining_attempts',greatest(5-v_new_count,0),'locked_until',v_lock_until);
    end if;
  end if;

  insert into public.business_security(business_id,delete_pin_hash,updated_at)
  values(p_bid,crypt(p_new_pin,gen_salt('bf',10)),now())
  on conflict(business_id) do update set delete_pin_hash=excluded.delete_pin_hash,updated_at=now();
  delete from public.security_key_attempts where business_id=p_bid and user_id=auth.uid();
  return jsonb_build_object('ok',true);
end;
$$;
revoke all on function public.set_delete_pin_v2(uuid,text,text) from public,anon;
grant execute on function public.set_delete_pin_v2(uuid,text,text) to authenticated;

create or replace function public.secure_delete_record_v2(p_bid uuid, p_entity text, p_record_id uuid, p_pin text)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_stored_hash text;
  v_att public.security_key_attempts%rowtype;
  v_new_count integer;
  v_lock_until timestamptz;
  v_affected integer:=0;
  v_sale_id uuid;
begin
  if auth.uid() is null or not public.has_business_role(p_bid,array['owner','admin']) then raise exception 'Hanya owner/admin yang dapat menghapus data permanen'; end if;
  if p_pin !~ '^[0-9]{6}$' then return jsonb_build_object('ok',false,'error','Security Key harus 6 digit'); end if;

  insert into public.security_key_attempts(business_id,user_id,failed_attempts,updated_at)
  values(p_bid,auth.uid(),0,now()) on conflict(business_id,user_id) do nothing;
  select * into v_att from public.security_key_attempts where business_id=p_bid and user_id=auth.uid() for update;
  if v_att.locked_until is not null and v_att.locked_until>now() then
    return jsonb_build_object('ok',false,'error','Security Key terkunci sementara','locked_until',v_att.locked_until);
  end if;

  select delete_pin_hash into v_stored_hash from public.business_security where business_id=p_bid;
  if v_stored_hash is null then return jsonb_build_object('ok',false,'error','Security Key belum diatur'); end if;
  if crypt(p_pin,v_stored_hash)<>v_stored_hash then
    v_new_count:=coalesce(v_att.failed_attempts,0)+1;
    v_lock_until:=case when v_new_count>=5 then now()+interval '15 minutes' else null end;
    update public.security_key_attempts set failed_attempts=case when v_new_count>=5 then 0 else v_new_count end,
      locked_until=v_lock_until,last_failed_at=now(),updated_at=now()
    where business_id=p_bid and user_id=auth.uid();
    return jsonb_build_object('ok',false,
      'error',case when v_lock_until is not null then 'Terlalu banyak percobaan. Security Key dikunci 15 menit.' else 'Security Key salah' end,
      'remaining_attempts',greatest(5-v_new_count,0),'locked_until',v_lock_until);
  end if;

  delete from public.security_key_attempts where business_id=p_bid and user_id=auth.uid();

  if p_entity='sale' then
    delete from public.sales where id=p_record_id and business_id=p_bid; get diagnostics v_affected=row_count;
  elsif p_entity='expense' then
    delete from public.expenses where id=p_record_id and business_id=p_bid; get diagnostics v_affected=row_count;
  elsif p_entity='payment' then
    select sale_id into v_sale_id from public.payments where id=p_record_id and business_id=p_bid;
    if v_sale_id is not null then perform 1 from public.sales where id=v_sale_id for update; end if;
    delete from public.payments where id=p_record_id and business_id=p_bid; get diagnostics v_affected=row_count;
  elsif p_entity='product' then
    if exists(select 1 from public.sales s where s.business_id=p_bid and s.product_id=p_record_id) then
      return jsonb_build_object('ok',false,'error','Produk sudah punya riwayat penjualan. Edit data produk saja.');
    end if;
    delete from public.products where id=p_record_id and business_id=p_bid; get diagnostics v_affected=row_count;
  else
    return jsonb_build_object('ok',false,'error','Jenis data tidak dikenal');
  end if;

  if v_affected=0 then return jsonb_build_object('ok',false,'error','Data tidak ditemukan'); end if;
  return jsonb_build_object('ok',true);
end;
$$;
revoke all on function public.secure_delete_record_v2(uuid,text,uuid,text) from public,anon;
grant execute on function public.secure_delete_record_v2(uuid,text,uuid,text) to authenticated;

-- Disable legacy mutation RPCs so new clients must use the hardened versions.
revoke execute on function public.secure_delete_record(uuid,text,uuid,text) from authenticated;
revoke execute on function public.set_delete_pin(uuid,text) from authenticated;

-- =========================================================
-- 7. Least-privilege Data API grants
-- =========================================================
-- Remove implicit/default rights first. Security-definer RPCs perform sensitive mutations.
revoke all on public.businesses,public.business_members,public.products,public.sales,public.expenses,public.payments,
  public.audit_logs,public.sync_events,public.document_sequences,public.business_security,public.security_key_attempts
from anon;

revoke all on public.businesses,public.business_members,public.products,public.sales,public.expenses,public.payments,
  public.audit_logs,public.sync_events,public.document_sequences,public.business_security,public.security_key_attempts
from authenticated;

-- Businesses: readable; users may create own business. Updates restricted to profile/settings columns.
grant select on public.businesses to authenticated;
grant insert(name,owner_id,allow_negative_stock) on public.businesses to authenticated;
grant update(name,address,phone,email,city,document_footer,allow_negative_stock) on public.businesses to authenticated;

-- Memberships are read-only from Data API; owner mutation is through dedicated RPCs.
grant select on public.business_members to authenticated;

-- Products: role/RLS + trigger protects warehouse. HPP is read only through list_products_for_business RPC.
grant select(id,business_id,client_request_id) on public.products to authenticated;
grant insert(business_id,sku,name,category,unit,cost,price,stock,min_stock,client_request_id) on public.products to authenticated;
grant update(sku,name,category,unit,cost,price,stock,min_stock) on public.products to authenticated;

-- Sales are read through role-safe RPC; create/update only through atomic RPCs.
-- No direct table SELECT/INSERT/UPDATE/DELETE grant.

-- Payments may be read by RLS-authorized financial/cashier roles; mutations only through record_payment / secure delete.
grant select on public.payments to authenticated;

-- Expenses remain CRUD-without-delete through RLS; deletes require Security Key RPC.
grant select on public.expenses to authenticated;
grant insert(business_id,date,category,description,amount,payment_method,client_request_id) on public.expenses to authenticated;
grant update(date,category,description,amount,payment_method) on public.expenses to authenticated;

-- Audit & sync are read-only.
grant select on public.audit_logs,public.sync_events to authenticated;

-- Existing role helpers / list RPCs remain executable.
grant execute on function public.business_role(uuid) to authenticated;
grant execute on function public.has_business_role(uuid,text[]) to authenticated;
grant execute on function public.can_access_business(uuid) to authenticated;
grant execute on function public.list_products_for_business(uuid) to authenticated;
grant execute on function public.list_sales_for_business(uuid) to authenticated;
revoke execute on function public.next_document_number(uuid,text,date) from authenticated;

commit;
