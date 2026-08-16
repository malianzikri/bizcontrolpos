-- BizControl Online V1.8.2 - staging fix
-- Purpose: create the first business server-side from auth.uid().
-- Safe to run on a V1.8.1 staging database.

begin;

alter table public.businesses
  add column if not exists allow_negative_stock boolean not null default false;

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
set search_path = pg_catalog, public, auth, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_name text := btrim(coalesce(p_name,''));
begin
  if v_uid is null then
    raise exception 'Sesi login tidak valid. Silakan login ulang.' using errcode='28000';
  end if;

  if length(v_name) < 2 then
    raise exception 'Nama bisnis minimal 2 karakter' using errcode='22023';
  end if;

  if length(v_name) > 120 then
    raise exception 'Nama bisnis maksimal 120 karakter' using errcode='22023';
  end if;

  return query
  insert into public.businesses as b(name, owner_id, allow_negative_stock)
  values(v_name, v_uid, false)
  returning
    b.id,b.name,b.address,b.phone,b.email,b.city,b.document_footer,
    b.owner_id,b.created_at,b.updated_at,b.allow_negative_stock;
end;
$$;

revoke all on function public.create_business(text) from public, anon, authenticated;
grant execute on function public.create_business(text) to authenticated;

-- Business creation is now RPC-only. Do not accept owner_id from the browser.
revoke insert(name,owner_id,allow_negative_stock) on public.businesses from authenticated;

commit;
