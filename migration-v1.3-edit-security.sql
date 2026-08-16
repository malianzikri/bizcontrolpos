-- BizControl Online V1.2 -> V1.3 migration
-- Run once in Supabase SQL Editor if V1.2 schema is already installed.

create extension if not exists pgcrypto;

create table if not exists public.business_security (
  business_id uuid primary key references public.businesses(id) on delete cascade,
  delete_pin_hash text not null,
  updated_at timestamptz not null default now()
);
alter table public.business_security enable row level security;
revoke all on table public.business_security from anon, authenticated;

drop policy if exists "products delete" on public.products;
drop policy if exists "sales delete" on public.sales;
drop policy if exists "expenses delete" on public.expenses;

create or replace function public.has_delete_pin(bid uuid)
returns boolean language plpgsql security definer set search_path=public stable as $$
begin
  if auth.uid() is null or not public.can_access_business(bid) then raise exception 'Akses bisnis ditolak'; end if;
  return exists(select 1 from public.business_security s where s.business_id=bid);
end; $$;

create or replace function public.set_delete_pin(bid uuid, pin text)
returns boolean language plpgsql security definer set search_path=public as $$
begin
  if auth.uid() is null then raise exception 'Harus login'; end if;
  if not exists(select 1 from public.businesses b where b.id=bid and b.owner_id=auth.uid()) then raise exception 'Hanya owner yang dapat mengatur Security Key'; end if;
  if pin !~ '^[0-9]{6}$' then raise exception 'Security Key harus 6 digit angka'; end if;
  insert into public.business_security(business_id,delete_pin_hash,updated_at)
  values (bid,crypt(pin,gen_salt('bf')),now())
  on conflict (business_id) do update set delete_pin_hash=excluded.delete_pin_hash,updated_at=now();
  return true;
end; $$;

create or replace function public.secure_delete_record(bid uuid, entity text, record_id uuid, pin text)
returns boolean language plpgsql security definer set search_path=public as $$
declare stored_hash text; affected integer:=0;
begin
  if auth.uid() is null or not public.can_access_business(bid) then raise exception 'Akses bisnis ditolak'; end if;
  select delete_pin_hash into stored_hash from public.business_security where business_id=bid;
  if stored_hash is null then raise exception 'Security Key belum diatur'; end if;
  if crypt(pin,stored_hash)<>stored_hash then raise exception 'Security Key salah'; end if;
  if entity='sale' then
    delete from public.sales where id=record_id and business_id=bid; get diagnostics affected=row_count;
  elsif entity='expense' then
    delete from public.expenses where id=record_id and business_id=bid; get diagnostics affected=row_count;
  elsif entity='product' then
    if exists(select 1 from public.sales s where s.business_id=bid and s.product_id=record_id) then raise exception 'Produk sudah punya riwayat penjualan. Edit data produk saja agar histori laporan tetap aman.'; end if;
    delete from public.products where id=record_id and business_id=bid; get diagnostics affected=row_count;
  else raise exception 'Jenis data tidak dikenal'; end if;
  if affected=0 then raise exception 'Data tidak ditemukan'; end if;
  return true;
end; $$;

revoke all on function public.has_delete_pin(uuid) from public;
revoke all on function public.set_delete_pin(uuid,text) from public;
revoke all on function public.secure_delete_record(uuid,text,uuid,text) from public;
grant execute on function public.has_delete_pin(uuid) to authenticated;
grant execute on function public.set_delete_pin(uuid,text) to authenticated;
grant execute on function public.secure_delete_record(uuid,text,uuid,text) to authenticated;
