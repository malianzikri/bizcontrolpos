-- BizControl Online V1.7 — Production Foundations
-- Jalankan SETELAH migration V1.6 pada project Supabase yang sudah ada.
-- Fondasi: role-based access, team management, idempotency, nomor dokumen atomik,
-- realtime publication, dan hardening operasi Cloud.

begin;

-- =========================================================
-- 1. Compatibility / data hardening
-- =========================================================
alter table public.sales add column if not exists updated_at timestamptz not null default now();
alter table public.expenses add column if not exists updated_at timestamptz not null default now();

alter table public.products add column if not exists client_request_id uuid;
alter table public.sales add column if not exists client_request_id uuid;
alter table public.sales add column if not exists delivery_no text;
alter table public.expenses add column if not exists client_request_id uuid;
alter table public.payments add column if not exists client_request_id uuid;
alter table public.payments add column if not exists receipt_no text;

create unique index if not exists uq_products_business_request
  on public.products(business_id,client_request_id) where client_request_id is not null;
create unique index if not exists uq_sales_business_request
  on public.sales(business_id,client_request_id) where client_request_id is not null;
create unique index if not exists uq_expenses_business_request
  on public.expenses(business_id,client_request_id) where client_request_id is not null;
create unique index if not exists uq_payments_business_request
  on public.payments(business_id,client_request_id) where client_request_id is not null;

-- Existing invoice numbers are preserved. New production numbers are guaranteed unique per business.
create unique index if not exists uq_sales_business_invoice
  on public.sales(business_id,invoice_no);
create unique index if not exists uq_sales_business_delivery
  on public.sales(business_id,delivery_no) where delivery_no is not null;
create unique index if not exists uq_payments_business_receipt
  on public.payments(business_id,receipt_no) where receipt_no is not null;

-- =========================================================
-- 2. Business roles
-- =========================================================
create or replace function public.business_role(bid uuid)
returns text
language sql
security definer
set search_path=public
stable
as $$
  select case
    when exists(select 1 from public.businesses b where b.id=bid and b.owner_id=auth.uid()) then 'owner'
    else coalesce((select m.role from public.business_members m where m.business_id=bid and m.user_id=auth.uid() limit 1),'none')
  end;
$$;

revoke all on function public.business_role(uuid) from public;
grant execute on function public.business_role(uuid) to authenticated;

create or replace function public.has_business_role(bid uuid, allowed_roles text[])
returns boolean
language sql
security definer
set search_path=public
stable
as $$
  select public.business_role(bid)=any(allowed_roles);
$$;

revoke all on function public.has_business_role(uuid,text[]) from public;
grant execute on function public.has_business_role(uuid,text[]) to authenticated;

-- Keep general access helper aligned with roles.
create or replace function public.can_access_business(bid uuid)
returns boolean
language sql
security definer
set search_path=public
stable
as $$
  select public.business_role(bid) <> 'none';
$$;

-- =========================================================
-- 3. Role-aware RLS policies
-- =========================================================
-- Businesses
 drop policy if exists "business select accessible" on public.businesses;
 drop policy if exists "business insert owner" on public.businesses;
 drop policy if exists "business update owner" on public.businesses;
 drop policy if exists "business delete owner" on public.businesses;
 drop policy if exists "business update owner admin" on public.businesses;
 create policy "business select accessible" on public.businesses for select
   using (public.can_access_business(id));
 create policy "business insert owner" on public.businesses for insert
   with check (owner_id=auth.uid());
 create policy "business update owner admin" on public.businesses for update
   using (public.has_business_role(id,array['owner','admin']))
   with check (public.has_business_role(id,array['owner','admin']));
 create policy "business delete owner" on public.businesses for delete
   using (owner_id=auth.uid());

-- Members: owner manages; user can always read own membership; admin can inspect through RPC.
 drop policy if exists "member select" on public.business_members;
 drop policy if exists "member insert owner" on public.business_members;
 drop policy if exists "member update owner" on public.business_members;
 drop policy if exists "member delete owner" on public.business_members;
 drop policy if exists "member select own or owner" on public.business_members;
 create policy "member select own or owner" on public.business_members for select
   using (user_id=auth.uid() or public.has_business_role(business_id,array['owner']));
 create policy "member insert owner" on public.business_members for insert
   with check (public.has_business_role(business_id,array['owner']));
 create policy "member update owner" on public.business_members for update
   using (public.has_business_role(business_id,array['owner']))
   with check (public.has_business_role(business_id,array['owner']));
 create policy "member delete owner" on public.business_members for delete
   using (public.has_business_role(business_id,array['owner']));

-- Products
 drop policy if exists "products select" on public.products;
 drop policy if exists "products insert" on public.products;
 drop policy if exists "products update" on public.products;
 drop policy if exists "products select by role" on public.products;
 drop policy if exists "products insert operational" on public.products;
 drop policy if exists "products update operational" on public.products;
 create policy "products select by role" on public.products for select
   using (public.has_business_role(business_id,array['owner','admin','cashier','finance','warehouse','staff']));
 create policy "products insert operational" on public.products for insert
   with check (public.has_business_role(business_id,array['owner','admin']));
 create policy "products update operational" on public.products for update
   using (public.has_business_role(business_id,array['owner','admin','warehouse']))
   with check (public.has_business_role(business_id,array['owner','admin','warehouse']));

-- Gudang may update stock thresholds only; price/HPP/master identity stay protected at DB level.
create or replace function public.guard_warehouse_product_update()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
begin
  if public.business_role(old.business_id)='warehouse' then
    if new.id is distinct from old.id
       or new.business_id is distinct from old.business_id
       or new.sku is distinct from old.sku
       or new.name is distinct from old.name
       or new.category is distinct from old.category
       or new.unit is distinct from old.unit
       or new.cost is distinct from old.cost
       or new.price is distinct from old.price
       or new.created_at is distinct from old.created_at
       or new.client_request_id is distinct from old.client_request_id then
      raise exception 'Role Gudang hanya boleh mengubah stok dan minimum stok';
    end if;
  end if;
  new.updated_at:=now();
  return new;
end;
$$;
revoke all on function public.guard_warehouse_product_update() from public;
drop trigger if exists trg_guard_warehouse_product_update on public.products;
create trigger trg_guard_warehouse_product_update
before update on public.products
for each row execute function public.guard_warehouse_product_update();

-- Sales
 drop policy if exists "sales select" on public.sales;
 drop policy if exists "sales insert" on public.sales;
 drop policy if exists "sales update" on public.sales;
 drop policy if exists "sales select operational" on public.sales;
 drop policy if exists "sales insert cashier" on public.sales;
 drop policy if exists "sales update cashier" on public.sales;
 create policy "sales select operational" on public.sales for select
   using (public.has_business_role(business_id,array['owner','admin','cashier','finance','warehouse']));
 create policy "sales insert cashier" on public.sales for insert
   with check (public.has_business_role(business_id,array['owner','admin','cashier']));
 create policy "sales update cashier" on public.sales for update
   using (public.has_business_role(business_id,array['owner','admin','cashier']))
   with check (public.has_business_role(business_id,array['owner','admin','cashier']));

-- Expenses
 drop policy if exists "expenses select" on public.expenses;
 drop policy if exists "expenses insert" on public.expenses;
 drop policy if exists "expenses update" on public.expenses;
 drop policy if exists "expenses select finance" on public.expenses;
 drop policy if exists "expenses insert finance" on public.expenses;
 drop policy if exists "expenses update finance" on public.expenses;
 create policy "expenses select finance" on public.expenses for select
   using (public.has_business_role(business_id,array['owner','admin','finance']));
 create policy "expenses insert finance" on public.expenses for insert
   with check (public.has_business_role(business_id,array['owner','admin','finance']));
 create policy "expenses update finance" on public.expenses for update
   using (public.has_business_role(business_id,array['owner','admin','finance']))
   with check (public.has_business_role(business_id,array['owner','admin','finance']));

-- Payments
 drop policy if exists "payments select" on public.payments;
 drop policy if exists "payments insert" on public.payments;
 drop policy if exists "payments update" on public.payments;
 drop policy if exists "payments select operational" on public.payments;
 drop policy if exists "payments insert operational" on public.payments;
 drop policy if exists "payments update operational" on public.payments;
 create policy "payments select operational" on public.payments for select
   using (public.has_business_role(business_id,array['owner','admin','cashier','finance']));
 create policy "payments insert operational" on public.payments for insert
   with check (public.has_business_role(business_id,array['owner','admin','cashier','finance']));
 create policy "payments update operational" on public.payments for update
   using (public.has_business_role(business_id,array['owner','admin','cashier','finance']))
   with check (public.has_business_role(business_id,array['owner','admin','cashier','finance']));

-- Audit Log: owner/admin only.
 drop policy if exists "audit select owner admin" on public.audit_logs;
 create policy "audit select owner admin" on public.audit_logs for select
   using (public.has_business_role(business_id,array['owner','admin']));

-- Direct deletes remain disabled. V1.3 secure RPC is the only path.
 drop policy if exists "products delete" on public.products;
 drop policy if exists "sales delete" on public.sales;
 drop policy if exists "expenses delete" on public.expenses;
 drop policy if exists "payments delete" on public.payments;
 revoke delete on public.products,public.sales,public.expenses,public.payments from anon,authenticated;

-- =========================================================
-- 4. Team management RPCs
-- =========================================================
create or replace function public.list_business_members(bid uuid)
returns table(user_id uuid,email text,role text,created_at timestamptz)
language plpgsql
security definer
set search_path=public,auth
stable
as $$
begin
  if auth.uid() is null or not public.has_business_role(bid,array['owner','admin']) then
    raise exception 'Hanya owner/admin yang dapat melihat tim';
  end if;
  return query
    select m.user_id,u.email::text,m.role,m.created_at
    from public.business_members m
    join auth.users u on u.id=m.user_id
    where m.business_id=bid
    order by m.created_at asc;
end;
$$;

create or replace function public.add_business_member_by_email(bid uuid, member_email text, new_role text)
returns uuid
language plpgsql
security definer
set search_path=public,auth
as $$
declare uid uuid;
begin
  if auth.uid() is null or public.business_role(bid)<>'owner' then raise exception 'Hanya owner yang dapat menambah anggota'; end if;
  if new_role not in ('admin','cashier','finance','warehouse','staff') then raise exception 'Role tidak valid'; end if;
  select id into uid from auth.users where lower(email)=lower(trim(member_email)) limit 1;
  if uid is null then raise exception 'Email belum terdaftar. Minta anggota membuat akun BizControl terlebih dahulu.'; end if;
  if exists(select 1 from public.businesses b where b.id=bid and b.owner_id=uid) then raise exception 'User tersebut adalah owner bisnis'; end if;
  insert into public.business_members(business_id,user_id,role)
  values(bid,uid,new_role)
  on conflict(business_id,user_id) do update set role=excluded.role;
  insert into public.audit_logs(business_id,actor_user_id,actor_email,action,module,record_id,record_label,before_data,after_data,created_at)
  values(bid,auth.uid(),coalesce(auth.jwt()->>'email','system'),'CREATE','team',uid,member_email,null,jsonb_build_object('email',member_email,'role',new_role),now());
  return uid;
end;
$$;

create or replace function public.update_business_member_role(bid uuid, member_user_id uuid, new_role text)
returns boolean
language plpgsql
security definer
set search_path=public,auth
as $$
declare old_role text; member_email text;
begin
  if auth.uid() is null or public.business_role(bid)<>'owner' then raise exception 'Hanya owner yang dapat mengubah role'; end if;
  if new_role not in ('admin','cashier','finance','warehouse','staff') then raise exception 'Role tidak valid'; end if;
  select m.role,u.email into old_role,member_email from public.business_members m join auth.users u on u.id=m.user_id where m.business_id=bid and m.user_id=member_user_id;
  if old_role is null then raise exception 'Anggota tidak ditemukan'; end if;
  update public.business_members set role=new_role where business_id=bid and user_id=member_user_id;
  insert into public.audit_logs(business_id,actor_user_id,actor_email,action,module,record_id,record_label,before_data,after_data,created_at)
  values(bid,auth.uid(),coalesce(auth.jwt()->>'email','system'),'UPDATE','team',member_user_id,member_email,jsonb_build_object('email',member_email,'role',old_role),jsonb_build_object('email',member_email,'role',new_role),now());
  return true;
end;
$$;

create or replace function public.remove_business_member(bid uuid, member_user_id uuid)
returns boolean
language plpgsql
security definer
set search_path=public,auth
as $$
declare old_role text; member_email text; affected int;
begin
  if auth.uid() is null or public.business_role(bid)<>'owner' then raise exception 'Hanya owner yang dapat menghapus anggota'; end if;
  select m.role,u.email into old_role,member_email from public.business_members m join auth.users u on u.id=m.user_id where m.business_id=bid and m.user_id=member_user_id;
  delete from public.business_members where business_id=bid and user_id=member_user_id;
  get diagnostics affected=row_count;
  if affected=0 then raise exception 'Anggota tidak ditemukan'; end if;
  insert into public.audit_logs(business_id,actor_user_id,actor_email,action,module,record_id,record_label,before_data,after_data,created_at)
  values(bid,auth.uid(),coalesce(auth.jwt()->>'email','system'),'DELETE','team',member_user_id,coalesce(member_email,member_user_id::text),jsonb_build_object('email',member_email,'role',old_role),null,now());
  return true;
end;
$$;

revoke all on function public.list_business_members(uuid) from public;
revoke all on function public.add_business_member_by_email(uuid,text,text) from public;
revoke all on function public.update_business_member_role(uuid,uuid,text) from public;
revoke all on function public.remove_business_member(uuid,uuid) from public;
grant execute on function public.list_business_members(uuid) to authenticated;
grant execute on function public.add_business_member_by_email(uuid,text,text) to authenticated;
grant execute on function public.update_business_member_role(uuid,uuid,text) to authenticated;
grant execute on function public.remove_business_member(uuid,uuid) to authenticated;

-- =========================================================
-- 5. Atomic document numbering
-- =========================================================
create table if not exists public.document_sequences(
  business_id uuid not null references public.businesses(id) on delete cascade,
  doc_type text not null check(doc_type in ('INV','KWT','SJ')),
  doc_year integer not null,
  last_number bigint not null default 0,
  updated_at timestamptz not null default now(),
  primary key(business_id,doc_type,doc_year)
);
alter table public.document_sequences enable row level security;
revoke all on public.document_sequences from anon,authenticated;

-- Initialize counters from any production-format numbers that already exist.
insert into public.document_sequences(business_id,doc_type,doc_year,last_number,updated_at)
select business_id,'INV',substring(invoice_no from '^INV-([0-9]{4})-[0-9]{6}$')::int,
       max(substring(invoice_no from '([0-9]{6})$')::bigint),now()
from public.sales
where invoice_no ~ '^INV-[0-9]{4}-[0-9]{6}$'
group by business_id,substring(invoice_no from '^INV-([0-9]{4})-[0-9]{6}$')::int
on conflict(business_id,doc_type,doc_year) do update
set last_number=greatest(public.document_sequences.last_number,excluded.last_number),updated_at=now();

insert into public.document_sequences(business_id,doc_type,doc_year,last_number,updated_at)
select business_id,'SJ',substring(delivery_no from '^SJ-([0-9]{4})-[0-9]{6}$')::int,
       max(substring(delivery_no from '([0-9]{6})$')::bigint),now()
from public.sales
where delivery_no ~ '^SJ-[0-9]{4}-[0-9]{6}$'
group by business_id,substring(delivery_no from '^SJ-([0-9]{4})-[0-9]{6}$')::int
on conflict(business_id,doc_type,doc_year) do update
set last_number=greatest(public.document_sequences.last_number,excluded.last_number),updated_at=now();

insert into public.document_sequences(business_id,doc_type,doc_year,last_number,updated_at)
select business_id,'KWT',substring(receipt_no from '^KWT-([0-9]{4})-[0-9]{6}$')::int,
       max(substring(receipt_no from '([0-9]{6})$')::bigint),now()
from public.payments
where receipt_no ~ '^KWT-[0-9]{4}-[0-9]{6}$'
group by business_id,substring(receipt_no from '^KWT-([0-9]{4})-[0-9]{6}$')::int
on conflict(business_id,doc_type,doc_year) do update
set last_number=greatest(public.document_sequences.last_number,excluded.last_number),updated_at=now();

create or replace function public.next_document_number(bid uuid, doc_type text, doc_date date default current_date)
returns text
language plpgsql
security definer
set search_path = pg_catalog, public, auth, extensions
as $$
declare
  v_year integer;
  v_number bigint;
  v_role text;
  v_doc_type text := upper(trim(coalesce($2,'')));
  v_doc_date date := coalesce($3,current_date);
begin
  if auth.uid() is null then raise exception 'Harus login'; end if;
  if v_doc_type not in ('INV','KWT','SJ') then raise exception 'Jenis dokumen tidak valid'; end if;
  v_role:=public.business_role($1);
  if v_doc_type in ('INV','SJ') and v_role not in ('owner','admin','cashier') then raise exception 'Role tidak boleh membuat dokumen penjualan'; end if;
  if v_doc_type='KWT' and v_role not in ('owner','admin','cashier','finance') then raise exception 'Role tidak boleh membuat kwitansi'; end if;
  v_year:=extract(year from v_doc_date)::int;
  insert into public.document_sequences as ds(business_id,doc_type,doc_year,last_number,updated_at)
  values($1,v_doc_type,v_year,1,now())
  on conflict on constraint document_sequences_pkey do update
    set last_number=ds.last_number+1,updated_at=now()
  returning last_number into v_number;
  return v_doc_type||'-'||v_year::text||'-'||lpad(v_number::text,6,'0');
end;
$$;

revoke all on function public.next_document_number(uuid,text,date) from public;
grant execute on function public.next_document_number(uuid,text,date) to authenticated;

-- =========================================================
-- 6. Secure delete role hardening
-- =========================================================
create or replace function public.secure_delete_record(bid uuid, entity text, record_id uuid, pin text)
returns boolean
language plpgsql
security definer
set search_path=public
as $$
declare stored_hash text; affected integer:=0;
begin
  if auth.uid() is null or not public.has_business_role(bid,array['owner','admin']) then raise exception 'Hanya owner/admin yang dapat menghapus data permanen'; end if;
  select delete_pin_hash into stored_hash from public.business_security where business_id=bid;
  if stored_hash is null then raise exception 'Security Key belum diatur'; end if;
  if crypt(pin,stored_hash)<>stored_hash then raise exception 'Security Key salah'; end if;
  if entity='sale' then
    delete from public.sales where id=record_id and business_id=bid; get diagnostics affected=row_count;
  elsif entity='expense' then
    delete from public.expenses where id=record_id and business_id=bid; get diagnostics affected=row_count;
  elsif entity='payment' then
    delete from public.payments where id=record_id and business_id=bid; get diagnostics affected=row_count;
  elsif entity='product' then
    if exists(select 1 from public.sales s where s.business_id=bid and s.product_id=record_id) then raise exception 'Produk sudah punya riwayat penjualan. Edit data produk saja.'; end if;
    delete from public.products where id=record_id and business_id=bid; get diagnostics affected=row_count;
  else raise exception 'Jenis data tidak dikenal';
  end if;
  if affected=0 then raise exception 'Data tidak ditemukan'; end if;
  return true;
end;
$$;
revoke all on function public.secure_delete_record(uuid,text,uuid,text) from public;
grant execute on function public.secure_delete_record(uuid,text,uuid,text) to authenticated;

-- Data API grants. RLS remains the authorization boundary.
grant select,insert,update on public.products,public.sales,public.expenses,public.payments to authenticated;
grant select on public.businesses,public.business_members,public.audit_logs to authenticated;

commit;

-- =========================================================
-- 7. Realtime publication (outside transaction for compatibility)
-- =========================================================
do $$
begin
  if not exists(select 1 from pg_publication where pubname='supabase_realtime') then
    execute 'create publication supabase_realtime';
  end if;
end $$;

do $$
declare t text;
begin
  foreach t in array array['products','sales','payments','expenses','audit_logs','business_members'] loop
    if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename=t) then
      execute format('alter publication supabase_realtime add table public.%I',t);
    end if;
  end loop;
end $$;

-- Previous-row payloads help multi-device refresh/debugging for UPDATE/DELETE.
alter table public.products replica identity full;
alter table public.sales replica identity full;
alter table public.payments replica identity full;
alter table public.expenses replica identity full;
alter table public.business_members replica identity full;

-- =========================================================
-- 8. Sensitive financial fields & safe read RPCs
-- =========================================================
-- Client roles must not be able to bypass the UI and read HPP/laba through direct REST queries.
-- Direct SELECT is limited to non-sensitive columns; authorized financial roles receive sensitive
-- fields through security-definer RPCs that mask values based on the business role.

revoke select on public.products from authenticated;
grant select (id,business_id,sku,name,category,unit,price,stock,min_stock,created_at,updated_at,client_request_id)
  on public.products to authenticated;

revoke select on public.sales from authenticated;
grant select (id,business_id,date,invoice_no,delivery_no,customer,customer_phone,customer_address,notes,
              product_id,product_name,qty,unit_price,discount,total,payment_method,paid_amount,
              created_at,updated_at,client_request_id)
  on public.sales to authenticated;

create or replace function public.list_products_for_business(bid uuid)
returns table(
  id uuid,business_id uuid,sku text,name text,category text,unit text,cost numeric,price numeric,
  stock numeric,min_stock numeric,created_at timestamptz,updated_at timestamptz,client_request_id uuid
)
language plpgsql
security definer
set search_path=public
stable
as $$
declare r text;
begin
  r:=public.business_role(bid);
  if r='none' then raise exception 'Tidak memiliki akses bisnis'; end if;
  return query
    select p.id,p.business_id,p.sku,p.name,p.category,p.unit,
           case when r in ('owner','admin','finance') then p.cost else null end,
           p.price,p.stock,p.min_stock,p.created_at,p.updated_at,p.client_request_id
    from public.products p where p.business_id=bid order by p.created_at asc;
end;
$$;
revoke all on function public.list_products_for_business(uuid) from public;
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
  if r not in ('owner','admin','cashier','finance','warehouse') then raise exception 'Tidak memiliki akses penjualan'; end if;
  return query
    select s.id,s.business_id,s.date,s.invoice_no,s.delivery_no,s.customer,s.customer_phone,s.customer_address,
           s.notes,s.product_id,s.product_name,s.qty,s.unit_price,
           case when r in ('owner','admin','finance') then s.unit_cost else null end,
           s.discount,s.total,
           case when r in ('owner','admin','finance') then s.gross_profit else null end,
           s.payment_method,s.paid_amount,s.created_at,s.updated_at,s.client_request_id
    from public.sales s where s.business_id=bid order by s.date desc,s.created_at desc;
end;
$$;
revoke all on function public.list_sales_for_business(uuid) from public;
grant execute on function public.list_sales_for_business(uuid) to authenticated;

-- Server owns sales financial calculations. This prevents client tampering and keeps HPP hidden from cashier/gudang.
create or replace function public.prepare_sale_financials()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare p_name text; p_cost numeric; p_price numeric; p_business uuid;
begin
  select name,cost,price,business_id into p_name,p_cost,p_price,p_business from public.products where id=new.product_id;
  if p_business is null then raise exception 'Produk tidak ditemukan'; end if;
  if p_business<>new.business_id then raise exception 'Produk dan transaksi harus berada pada bisnis yang sama'; end if;
  if tg_op='INSERT' then
    new.product_name:=p_name;
    new.unit_cost:=p_cost;
    new.unit_price:=p_price;
  else
    -- Nomor dokumen tidak dapat diganti setelah transaksi dibuat.
    new.invoice_no:=old.invoice_no;
    new.delivery_no:=old.delivery_no;
    -- paid_amount adalah cache dari tabel payments. Direct PATCH tidak boleh mengubahnya.
    if new.paid_amount is distinct from old.paid_amount and pg_trigger_depth()<=1 then
      raise exception 'Jumlah dibayar hanya boleh berubah melalui Riwayat Pembayaran';
    end if;
    if new.product_id is distinct from old.product_id then
      new.product_name:=p_name;
      new.unit_cost:=p_cost;
      new.unit_price:=p_price;
    else
      new.product_name:=old.product_name;
      new.unit_cost:=old.unit_cost;
      new.unit_price:=old.unit_price;
    end if;
  end if;
  new.discount:=greatest(coalesce(new.discount,0),0);
  new.total:=greatest(new.qty*new.unit_price-new.discount,0);
  new.gross_profit:=new.total-(new.qty*new.unit_cost);
  new.updated_at:=now();
  return new;
end;
$$;
revoke all on function public.prepare_sale_financials() from public;
drop trigger if exists trg_prepare_sale_financials on public.sales;
create trigger trg_prepare_sale_financials
before insert or update on public.sales
for each row execute function public.prepare_sale_financials();

-- =========================================================
-- 9. Minimal Realtime event stream
-- =========================================================
-- Realtime listens to this non-sensitive stream, then refetches role-safe data through RPC/RLS.
create table if not exists public.sync_events(
  id bigint generated by default as identity primary key,
  business_id uuid not null references public.businesses(id) on delete cascade,
  entity text not null,
  record_id uuid,
  event_type text not null,
  changed_at timestamptz not null default now()
);
alter table public.sync_events enable row level security;
drop policy if exists "sync events read accessible" on public.sync_events;
create policy "sync events read accessible" on public.sync_events for select
  using (public.can_access_business(business_id));
revoke all on public.sync_events from anon,authenticated;
grant select on public.sync_events to authenticated;

create or replace function public.emit_sync_event()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare bid uuid; rid uuid;
begin
  bid:=case when tg_op='DELETE' then old.business_id else new.business_id end;
  rid:=case when tg_op='DELETE' then old.id else new.id end;
  insert into public.sync_events(business_id,entity,record_id,event_type,changed_at)
  values(bid,tg_table_name,rid,tg_op,now());
  return case when tg_op='DELETE' then old else new end;
end;
$$;
revoke all on function public.emit_sync_event() from public;

-- Re-create event triggers idempotently.
do $$
declare t text;
begin
  foreach t in array array['products','sales','payments','expenses','audit_logs'] loop
    execute format('drop trigger if exists trg_sync_%I on public.%I',t,t);
    execute format('create trigger trg_sync_%I after insert or update or delete on public.%I for each row execute function public.emit_sync_event()',t,t);
  end loop;
end $$;

drop trigger if exists trg_sync_business_members on public.business_members;
create trigger trg_sync_business_members
after insert or update or delete on public.business_members
for each row execute function public.emit_sync_event();

do $$
begin
  if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='sync_events') then
    execute 'alter publication supabase_realtime add table public.sync_events';
  end if;
end $$;
alter table public.sync_events replica identity full;


-- Payment document identity is immutable after creation.
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
    new.business_id:=old.business_id;
    new.sale_id:=old.sale_id;
    new.payment_no:=old.payment_no;
    new.receipt_no:=old.receipt_no;
    new.client_request_id:=old.client_request_id;
  end if;
  select total,business_id into sale_total,sale_business from public.sales where id=new.sale_id;
  if sale_total is null then raise exception 'Invoice tidak ditemukan'; end if;
  if new.business_id <> sale_business then raise exception 'Pembayaran dan invoice harus berada pada bisnis yang sama'; end if;
  if tg_op='INSERT' and coalesce(new.payment_no,0)<=0 then
    select coalesce(max(payment_no),0)+1 into new.payment_no from public.payments where sale_id=new.sale_id;
  end if;
  select coalesce(sum(amount),0) into other_paid from public.payments
    where sale_id=new.sale_id and (tg_op='INSERT' or id<>new.id);
  if other_paid+new.amount>sale_total+0.005 then raise exception 'Pembayaran melebihi sisa tagihan'; end if;
  new.updated_at:=now();
  if new.created_by is null then new.created_by:=auth.uid(); end if;
  return new;
end;
$$;
revoke all on function public.prepare_payment() from public;

-- V1.7 clients only need the non-sensitive sync_events stream.
-- Remove legacy base tables from the publication to reduce accidental payload exposure.
do $$
declare t text;
begin
  foreach t in array array['products','sales','payments','expenses','audit_logs','business_members'] loop
    if exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename=t) then
      execute format('alter publication supabase_realtime drop table public.%I',t);
    end if;
  end loop;
end $$;
