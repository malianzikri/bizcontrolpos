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
