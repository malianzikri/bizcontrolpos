-- BizControl Online V1.5 — Invoice, Kwitansi, Surat Jalan
-- Jalankan SETELAH schema/migration V1.4 pada project Supabase yang sudah ada.

begin;

-- Profil usaha untuk header/footer dokumen cetak.
alter table public.businesses add column if not exists address text;
alter table public.businesses add column if not exists phone text;
alter table public.businesses add column if not exists email text;
alter table public.businesses add column if not exists city text;
alter table public.businesses add column if not exists document_footer text;

-- Data customer yang diperlukan Invoice/Surat Jalan.
alter table public.sales add column if not exists customer_phone text;
alter table public.sales add column if not exists customer_address text;
alter table public.sales add column if not exists notes text;

commit;

-- Tidak ada policy tambahan yang diperlukan:
-- kolom baru mengikuti RLS businesses/sales yang sudah ada.
-- Trigger audit V1.4 memakai to_jsonb(new/old), sehingga kolom baru otomatis ikut tercatat.

-- Audit perubahan Profil Dokumen Bisnis (V1.4 audit_logs harus sudah tersedia).
create or replace function public.write_business_profile_audit()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
begin
  if (to_jsonb(new) - 'updated_at') is distinct from (to_jsonb(old) - 'updated_at') then
    insert into public.audit_logs(
      business_id, actor_user_id, actor_email, action, module,
      record_id, record_label, before_data, after_data, created_at
    ) values (
      new.id,
      auth.uid(),
      coalesce(auth.jwt() ->> 'email','system'),
      'UPDATE','business',new.id,new.name,
      to_jsonb(old),to_jsonb(new),now()
    );
  end if;
  return null;
end;
$$;

revoke all on function public.write_business_profile_audit() from public;

drop trigger if exists trg_audit_business_profile on public.businesses;
create trigger trg_audit_business_profile
after update on public.businesses
for each row execute function public.write_business_profile_audit();
