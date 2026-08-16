-- BizControl V1.8.1 — RESUME after fresh-schema updated_at error
-- Use this ONLY when the original Fresh Schema already stopped at:
--   column "updated_at" of relation "sales" does not exist
-- Earlier V1.x base objects already exist; this file repairs the missing columns
-- and continues safely from the V1.6 Payment History block onward.

rollback;

alter table public.sales
  add column if not exists updated_at timestamptz not null default now();

alter table public.expenses
  add column if not exists updated_at timestamptz not null default now();

-- Verify compatibility columns before continuing.
do $$
begin
  if not exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='sales' and column_name='updated_at'
  ) then raise exception 'sales.updated_at repair failed'; end if;
end $$;

-- =========================================================
-- V1.6 Payment History
-- =========================================================
-- BizControl Online V1.6 — Riwayat Pembayaran per Invoice
-- Jalankan SETELAH migration V1.5 pada project Supabase yang sudah ada.
-- Tujuan: setiap DP/cicilan/pelunasan menjadi record sendiri, paid_amount invoice otomatis,
-- kwitansi bisa dicetak per pembayaran, dan seluruh perubahan masuk Audit Log.

begin;

create table if not exists public.payments (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  sale_id uuid not null references public.sales(id) on delete cascade,
  payment_no integer not null default 0,
  payment_date date not null default current_date,
  amount numeric(18,2) not null check (amount > 0),
  method text not null default 'Cash',
  notes text,
  created_by uuid references auth.users(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists idx_payments_sale_no on public.payments(sale_id,payment_no);
create index if not exists idx_payments_business_date on public.payments(business_id,payment_date desc);
create index if not exists idx_payments_sale on public.payments(sale_id);

-- Nomor pembayaran otomatis dan validasi supaya total pembayaran tidak melebihi invoice.
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
  select total,business_id into sale_total,sale_business from public.sales where id=new.sale_id;
  if sale_total is null then raise exception 'Invoice tidak ditemukan'; end if;
  if new.business_id <> sale_business then raise exception 'Pembayaran dan invoice harus berada pada bisnis yang sama'; end if;

  if tg_op='INSERT' and coalesce(new.payment_no,0)<=0 then
    select coalesce(max(payment_no),0)+1 into new.payment_no from public.payments where sale_id=new.sale_id;
  end if;

  select coalesce(sum(amount),0) into other_paid
  from public.payments
  where sale_id=new.sale_id
    and (tg_op='INSERT' or id<>new.id);

  if other_paid + new.amount > sale_total + 0.005 then
    raise exception 'Pembayaran melebihi sisa tagihan';
  end if;

  new.updated_at:=now();
  if new.created_by is null then new.created_by:=auth.uid(); end if;
  return new;
end;
$$;

revoke all on function public.prepare_payment() from public;

drop trigger if exists trg_prepare_payment on public.payments;
create trigger trg_prepare_payment
before insert or update on public.payments
for each row execute function public.prepare_payment();

-- paid_amount pada sales menjadi cache/summary dari tabel payments.
create or replace function public.recalculate_sale_paid_amount()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare
  sid uuid;
  v_paid numeric(18,2);
begin
  sid:=case when tg_op='DELETE' then old.sale_id else new.sale_id end;
  select coalesce(sum(amount),0) into v_paid from public.payments where sale_id=sid;
  update public.sales
    set paid_amount=least(total,v_paid), updated_at=now()
    where id=sid and paid_amount is distinct from least(total,v_paid);
  return null;
end;
$$;

revoke all on function public.recalculate_sale_paid_amount() from public;

drop trigger if exists trg_recalculate_sale_paid on public.payments;
create trigger trg_recalculate_sale_paid
after insert or update or delete on public.payments
for each row execute function public.recalculate_sale_paid_amount();

-- Migrasi pembayaran V1.5: paid_amount lama dibuat sebagai Pembayaran #1 jika belum ada history.
insert into public.payments(business_id,sale_id,payment_no,payment_date,amount,method,notes,created_at)
select s.business_id,s.id,1,s.date,s.paid_amount,coalesce(nullif(s.payment_method,''),'Transfer'),
       'Migrasi saldo pembayaran dari BizControl V1.5',coalesce(s.created_at,now())
from public.sales s
where coalesce(s.paid_amount,0)>0
  and not exists(select 1 from public.payments p where p.sale_id=s.id);

-- Sinkronkan ulang seluruh paid_amount setelah migrasi.
update public.sales s
set paid_amount=least(s.total,coalesce((select sum(p.amount) from public.payments p where p.sale_id=s.id),0)),
    updated_at=now();

-- RLS: user yang memiliki akses bisnis dapat melihat/menambah/mengedit pembayaran.
alter table public.payments enable row level security;

drop policy if exists "payments select" on public.payments;
create policy "payments select" on public.payments for select
using (public.can_access_business(business_id));

drop policy if exists "payments insert" on public.payments;
create policy "payments insert" on public.payments for insert
with check (public.can_access_business(business_id));

drop policy if exists "payments update" on public.payments;
create policy "payments update" on public.payments for update
using (public.can_access_business(business_id)) with check (public.can_access_business(business_id));

-- Tidak ada direct DELETE policy. Hapus pembayaran wajib melalui secure_delete_record + Security Key.
drop policy if exists "payments delete" on public.payments;

grant select,insert,update on public.payments to authenticated;
revoke delete on public.payments from anon,authenticated;

-- Audit Log V1.4 diperluas untuk label pembayaran yang lebih mudah dibaca.
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
  sid uuid;
  inv text;
begin
  bid := case when tg_op='DELETE' then old.business_id else new.business_id end;
  rid := case when tg_op='DELETE' then old.id else new.id end;
  before_json := case when tg_op in ('UPDATE','DELETE') then to_jsonb(old) else null end;
  after_json := case when tg_op in ('INSERT','UPDATE') then to_jsonb(new) else null end;
  module_name := tg_table_name;

  if tg_table_name='products' then
    label := coalesce(case when tg_op='DELETE' then old.sku else new.sku end,'') || ' · ' || coalesce(case when tg_op='DELETE' then old.name else new.name end,'');
    if tg_op='UPDATE'
       and new.stock is distinct from old.stock
       and (to_jsonb(new) - 'stock' - 'updated_at') = (to_jsonb(old) - 'stock' - 'updated_at') then
      module_name := 'stock';
    end if;
  elsif tg_table_name='sales' then
    -- paid_amount berubah otomatis dari tabel payments; jangan buat log sales duplikat jika hanya cache pembayaran yang berubah.
    if tg_op='UPDATE'
       and new.paid_amount is distinct from old.paid_amount
       and (to_jsonb(new) - 'paid_amount' - 'updated_at') = (to_jsonb(old) - 'paid_amount' - 'updated_at') then
      return null;
    end if;
    label := coalesce(case when tg_op='DELETE' then old.invoice_no else new.invoice_no end,'') ||
      case when coalesce(case when tg_op='DELETE' then old.customer else new.customer end,'')<>''
        then ' · ' || coalesce(case when tg_op='DELETE' then old.customer else new.customer end,'') else '' end;
  elsif tg_table_name='payments' then
    sid := case when tg_op='DELETE' then old.sale_id else new.sale_id end;
    select invoice_no into inv from public.sales where id=sid;
    label := coalesce(inv,'Invoice') || ' · Pembayaran #' || coalesce((case when tg_op='DELETE' then old.payment_no else new.payment_no end)::text,'-');
  elsif tg_table_name='expenses' then
    label := coalesce(case when tg_op='DELETE' then old.description else new.description end,'Biaya');
  else
    label := coalesce(rid::text,'Data');
  end if;

  insert into public.audit_logs(
    business_id, actor_user_id, actor_email, action, module,
    record_id, record_label, before_data, after_data, created_at
  ) values (
    bid,auth.uid(),coalesce(auth.jwt() ->> 'email','system'),
    case tg_op when 'INSERT' then 'CREATE' when 'UPDATE' then 'UPDATE' else 'DELETE' end,
    module_name,rid,label,before_json,after_json,now()
  );
  return null;
end;
$$;

revoke all on function public.write_business_audit() from public;

drop trigger if exists trg_audit_payments on public.payments;
create trigger trg_audit_payments
after insert or update or delete on public.payments
for each row execute function public.write_business_audit();

-- Secure delete V1.3 diperluas untuk pembayaran.
create or replace function public.secure_delete_record(bid uuid, entity text, record_id uuid, pin text)
returns boolean
language plpgsql
security definer
set search_path=public
as $$
declare
  stored_hash text;
  affected integer := 0;
begin
  if auth.uid() is null or not public.can_access_business(bid) then raise exception 'Akses bisnis ditolak'; end if;
  select delete_pin_hash into stored_hash from public.business_security where business_id=bid;
  if stored_hash is null then raise exception 'Security Key belum diatur'; end if;
  if crypt(pin,stored_hash)<>stored_hash then raise exception 'Security Key salah'; end if;

  if entity='sale' then
    delete from public.sales where id=record_id and business_id=bid;
    get diagnostics affected=row_count;
  elsif entity='expense' then
    delete from public.expenses where id=record_id and business_id=bid;
    get diagnostics affected=row_count;
  elsif entity='payment' then
    delete from public.payments where id=record_id and business_id=bid;
    get diagnostics affected=row_count;
  elsif entity='product' then
    if exists(select 1 from public.sales s where s.business_id=bid and s.product_id=record_id) then
      raise exception 'Produk sudah punya riwayat penjualan. Edit data produk saja agar histori laporan tetap aman.';
    end if;
    delete from public.products where id=record_id and business_id=bid;
    get diagnostics affected=row_count;
  else
    raise exception 'Jenis data tidak dikenal';
  end if;

  if affected=0 then raise exception 'Data tidak ditemukan'; end if;
  return true;
end;
$$;

revoke all on function public.secure_delete_record(uuid,text,uuid,text) from public;
grant execute on function public.secure_delete_record(uuid,text,uuid,text) to authenticated;

commit;


-- ===== V1.7 PRODUCTION FOUNDATIONS =====
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
set search_path=public
as $$
declare y integer; n bigint; r text;
begin
  if auth.uid() is null then raise exception 'Harus login'; end if;
  if doc_type not in ('INV','KWT','SJ') then raise exception 'Jenis dokumen tidak valid'; end if;
  r:=public.business_role(bid);
  if doc_type in ('INV','SJ') and r not in ('owner','admin','cashier') then raise exception 'Role tidak boleh membuat dokumen penjualan'; end if;
  if doc_type='KWT' and r not in ('owner','admin','cashier','finance') then raise exception 'Role tidak boleh membuat kwitansi'; end if;
  y:=extract(year from coalesce(doc_date,current_date))::int;
  insert into public.document_sequences(business_id,doc_type,doc_year,last_number,updated_at)
  values(bid,doc_type,y,1,now())
  on conflict(business_id,doc_type,doc_year) do update
    set last_number=public.document_sequences.last_number+1,updated_at=now()
  returning last_number into n;
  return doc_type||'-'||y::text||'-'||lpad(n::text,6,'0');
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


-- ===== V1.8.1 PRODUCTION PATCH =====
-- BizControl Online V1.8.1 Production Patch
-- Apply AFTER V1.8 security-hardening migration.
-- Goals:
-- 1) Prevent HPP/gross-profit leakage through mutation RPC responses.
-- 2) Make future Data API exposure opt-in with default privilege revocation.
-- 3) Harden SECURITY DEFINER search_path and schema creation privileges.
-- 4) Revoke legacy/unneeded RPC execution and explicitly re-grant the production API surface.

begin;

-- =========================================================
-- 1. Schema + default privilege hardening
-- =========================================================
-- Authenticated clients never need CREATE in the exposed public schema.
revoke create on schema public from public, anon, authenticated;

grant usage on schema public to anon, authenticated;

-- Supabase existing projects may auto-grant privileges on newly-created objects.
-- Keep future tables/functions/sequences private until explicitly granted.
alter default privileges for role postgres in schema public
  revoke select, insert, update, delete on tables from anon, authenticated, service_role;

alter default privileges for role postgres in schema public
  revoke execute on functions from anon, authenticated, service_role;

alter default privileges for role postgres in schema public
  revoke usage, select on sequences from anon, authenticated, service_role;

alter default privileges for role postgres in schema public
  revoke execute on functions from public;

-- Existing functions: deny direct execution first; only the production RPC surface is re-granted below.
revoke execute on all functions in schema public from public, anon, authenticated;

-- =========================================================
-- 2. Fixed search_path for SECURITY DEFINER functions
-- =========================================================
-- A fixed trusted path + no client CREATE privilege prevents object-shadowing attacks.
-- `auth` is required by team-management functions and `extensions` by pgcrypto helpers.
alter function public.can_access_business(uuid) set search_path to pg_catalog, public, auth, extensions;
alter function public.apply_sale_stock() set search_path to pg_catalog, public, auth, extensions;
alter function public.has_delete_pin(uuid) set search_path to pg_catalog, public, auth, extensions;
alter function public.set_delete_pin(uuid,text) set search_path to pg_catalog, public, auth, extensions;
alter function public.secure_delete_record(uuid,text,uuid,text) set search_path to pg_catalog, public, auth, extensions;
alter function public.write_business_audit() set search_path to pg_catalog, public, auth, extensions;
alter function public.write_business_profile_audit() set search_path to pg_catalog, public, auth, extensions;
alter function public.prepare_payment() set search_path to pg_catalog, public, auth, extensions;
alter function public.recalculate_sale_paid_amount() set search_path to pg_catalog, public, auth, extensions;
alter function public.business_role(uuid) set search_path to pg_catalog, public, auth, extensions;
alter function public.has_business_role(uuid,text[]) set search_path to pg_catalog, public, auth, extensions;
alter function public.guard_warehouse_product_update() set search_path to pg_catalog, public, auth, extensions;
alter function public.list_business_members(uuid) set search_path to pg_catalog, public, auth, extensions;
alter function public.add_business_member_by_email(uuid,text,text) set search_path to pg_catalog, public, auth, extensions;
alter function public.update_business_member_role(uuid,uuid,text) set search_path to pg_catalog, public, auth, extensions;
alter function public.remove_business_member(uuid,uuid) set search_path to pg_catalog, public, auth, extensions;
alter function public.next_document_number(uuid,text,date) set search_path to pg_catalog, public, auth, extensions;
alter function public.list_products_for_business(uuid) set search_path to pg_catalog, public, auth, extensions;
alter function public.list_sales_for_business(uuid) set search_path to pg_catalog, public, auth, extensions;
alter function public.prepare_sale_financials() set search_path to pg_catalog, public, auth, extensions;
alter function public.emit_sync_event() set search_path to pg_catalog, public, auth, extensions;
alter function public.guard_business_identity() set search_path to pg_catalog, public, auth, extensions;
alter function public.guard_product_update_v18() set search_path to pg_catalog, public, auth, extensions;
alter function public.guard_expense_update_v18() set search_path to pg_catalog, public, auth, extensions;
alter function public.guard_member_identity_v18() set search_path to pg_catalog, public, auth, extensions;
alter function public.create_sale_with_payment(uuid,date,text,text,text,text,uuid,numeric,numeric,text,numeric,uuid) set search_path to pg_catalog, public, auth, extensions;
alter function public.update_sale_secure(uuid,uuid,date,text,text,text,text,uuid,numeric,numeric,text) set search_path to pg_catalog, public, auth, extensions;
alter function public.record_payment(uuid,uuid,uuid,date,numeric,text,text,uuid) set search_path to pg_catalog, public, auth, extensions;
alter function public.set_delete_pin_v2(uuid,text,text) set search_path to pg_catalog, public, auth, extensions;
alter function public.secure_delete_record_v2(uuid,text,uuid,text) set search_path to pg_catalog, public, auth, extensions;

-- =========================================================
-- 3. Mutation RPC response hardening
-- =========================================================
-- IMPORTANT: sale mutation responses intentionally NEVER contain unit_cost or gross_profit,
-- even when the caller is owner/admin. Clients reload role-filtered data through list_sales_for_business().
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
set search_path to pg_catalog, public, auth, extensions
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
  v_sale_json jsonb;
  v_payment_json jsonb;
begin
  v_role:=public.business_role(p_bid);
  if v_role not in ('owner','admin','cashier') then raise exception 'Role tidak boleh membuat penjualan'; end if;

  select x.id into v_existing_id from public.sales x
    where x.business_id=p_bid and x.client_request_id=v_request_id limit 1;

  if v_existing_id is not null then
    select * into v_sale from public.sales where id=v_existing_id;
    select * into v_payment from public.payments where sale_id=v_existing_id order by payment_no asc limit 1;
    v_sale_json:=jsonb_build_object(
      'id',v_sale.id,'business_id',v_sale.business_id,'date',v_sale.date,
      'invoice_no',v_sale.invoice_no,'delivery_no',v_sale.delivery_no,
      'customer',v_sale.customer,'customer_phone',v_sale.customer_phone,'customer_address',v_sale.customer_address,
      'notes',v_sale.notes,'product_id',v_sale.product_id,'product_name',v_sale.product_name,'qty',v_sale.qty,
      'unit_price',v_sale.unit_price,'discount',v_sale.discount,'total',v_sale.total,
      'payment_method',v_sale.payment_method,'paid_amount',v_sale.paid_amount,'client_request_id',v_sale.client_request_id
    );
    if v_payment.id is not null then
      v_payment_json:=jsonb_build_object(
        'id',v_payment.id,'business_id',v_payment.business_id,'sale_id',v_payment.sale_id,'payment_no',v_payment.payment_no,
        'payment_date',v_payment.payment_date,'amount',v_payment.amount,'method',v_payment.method,'notes',v_payment.notes,
        'receipt_no',v_payment.receipt_no,'client_request_id',v_payment.client_request_id
      );
    end if;
    return jsonb_build_object('ok',true,'duplicate',true,'sale',v_sale_json,'payment',v_payment_json);
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
  v_sale_json:=jsonb_build_object(
    'id',v_sale.id,'business_id',v_sale.business_id,'date',v_sale.date,
    'invoice_no',v_sale.invoice_no,'delivery_no',v_sale.delivery_no,
    'customer',v_sale.customer,'customer_phone',v_sale.customer_phone,'customer_address',v_sale.customer_address,
    'notes',v_sale.notes,'product_id',v_sale.product_id,'product_name',v_sale.product_name,'qty',v_sale.qty,
    'unit_price',v_sale.unit_price,'discount',v_sale.discount,'total',v_sale.total,
    'payment_method',v_sale.payment_method,'paid_amount',v_sale.paid_amount,'client_request_id',v_sale.client_request_id
  );
  if v_payment.id is not null then
    v_payment_json:=jsonb_build_object(
      'id',v_payment.id,'business_id',v_payment.business_id,'sale_id',v_payment.sale_id,'payment_no',v_payment.payment_no,
      'payment_date',v_payment.payment_date,'amount',v_payment.amount,'method',v_payment.method,'notes',v_payment.notes,
      'receipt_no',v_payment.receipt_no,'client_request_id',v_payment.client_request_id
    );
  end if;
  return jsonb_build_object('ok',true,'duplicate',false,'sale',v_sale_json,'payment',v_payment_json);
end;
$$;

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
set search_path to pg_catalog, public, auth, extensions
as $$
declare
  v_role text;
  v_sale public.sales%rowtype;
  v_sale_json jsonb;
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

  v_sale_json:=jsonb_build_object(
    'id',v_sale.id,'business_id',v_sale.business_id,'date',v_sale.date,
    'invoice_no',v_sale.invoice_no,'delivery_no',v_sale.delivery_no,
    'customer',v_sale.customer,'customer_phone',v_sale.customer_phone,'customer_address',v_sale.customer_address,
    'notes',v_sale.notes,'product_id',v_sale.product_id,'product_name',v_sale.product_name,'qty',v_sale.qty,
    'unit_price',v_sale.unit_price,'discount',v_sale.discount,'total',v_sale.total,
    'payment_method',v_sale.payment_method,'paid_amount',v_sale.paid_amount,'client_request_id',v_sale.client_request_id
  );
  return jsonb_build_object('ok',true,'sale',v_sale_json);
end;
$$;

-- =========================================================
-- 4. Explicit production API surface
-- =========================================================
-- Read helpers required by RLS and the app.
grant execute on function public.business_role(uuid) to authenticated;
grant execute on function public.has_business_role(uuid,text[]) to authenticated;
grant execute on function public.can_access_business(uuid) to authenticated;
grant execute on function public.has_delete_pin(uuid) to authenticated;

-- Safe list RPCs.
grant execute on function public.list_products_for_business(uuid) to authenticated;
grant execute on function public.list_sales_for_business(uuid) to authenticated;
grant execute on function public.list_business_members(uuid) to authenticated;

-- Owner/team mutations.
grant execute on function public.add_business_member_by_email(uuid,text,text) to authenticated;
grant execute on function public.update_business_member_role(uuid,uuid,text) to authenticated;
grant execute on function public.remove_business_member(uuid,uuid) to authenticated;

-- Transaction mutations.
grant execute on function public.create_sale_with_payment(uuid,date,text,text,text,text,uuid,numeric,numeric,text,numeric,uuid) to authenticated;
grant execute on function public.update_sale_secure(uuid,uuid,date,text,text,text,text,uuid,numeric,numeric,text) to authenticated;
grant execute on function public.record_payment(uuid,uuid,uuid,date,numeric,text,text,uuid) to authenticated;
grant execute on function public.set_delete_pin_v2(uuid,text,text) to authenticated;
grant execute on function public.secure_delete_record_v2(uuid,text,uuid,text) to authenticated;

-- Explicitly keep legacy/higher-risk helpers unavailable to browser clients.
revoke execute on function public.next_document_number(uuid,text,date) from public,anon,authenticated;
revoke execute on function public.set_delete_pin(uuid,text) from public,anon,authenticated;
revoke execute on function public.secure_delete_record(uuid,text,uuid,text) from public,anon,authenticated;

commit;
