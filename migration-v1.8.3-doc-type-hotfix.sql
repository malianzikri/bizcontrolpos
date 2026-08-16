-- BizControl Online V1.8.3 - Staging DB Hotfix
-- Fix: PL/pgSQL ambiguity between function parameter doc_type
-- and document_sequences.doc_type during document number generation.

begin;

create or replace function public.next_document_number(
  bid uuid,
  doc_type text,
  doc_date date default current_date
)
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
  if auth.uid() is null then
    raise exception 'Harus login';
  end if;

  if v_doc_type not in ('INV','KWT','SJ') then
    raise exception 'Jenis dokumen tidak valid';
  end if;

  v_role := public.business_role($1);

  if v_doc_type in ('INV','SJ') and v_role not in ('owner','admin','cashier') then
    raise exception 'Role tidak boleh membuat dokumen penjualan';
  end if;

  if v_doc_type = 'KWT' and v_role not in ('owner','admin','cashier','finance') then
    raise exception 'Role tidak boleh membuat kwitansi';
  end if;

  v_year := extract(year from v_doc_date)::int;

  insert into public.document_sequences as ds
    (business_id, doc_type, doc_year, last_number, updated_at)
  values
    ($1, v_doc_type, v_year, 1, now())
  on conflict on constraint document_sequences_pkey
  do update set
    last_number = ds.last_number + 1,
    updated_at = now()
  returning last_number into v_number;

  return v_doc_type || '-' || v_year::text || '-' || lpad(v_number::text,6,'0');
end;
$$;

-- Helper ini hanya dipanggil oleh RPC mutation SECURITY DEFINER.
-- Jangan expose langsung ke browser roles.
revoke all on function public.next_document_number(uuid,text,date)
  from public, anon, authenticated;

commit;
