-- BizControl Online V1.8.6 — Multi-Item Cashier
-- Jalankan SETELAH V1.8.5 / V1.8.4.1 staging.
-- Tujuan: satu invoice dapat berisi banyak barang/jasa, stok tetap atomik, pembayaran tetap per invoice.

begin;

-- =========================================================
-- 1. Sale line items
-- =========================================================
create table if not exists public.sale_items (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  sale_id uuid not null references public.sales(id) on delete cascade,
  line_no integer not null,
  product_id uuid not null references public.products(id),
  product_name text not null,
  unit text not null default 'pcs',
  qty numeric(18,2) not null check (qty > 0),
  unit_price numeric(18,2) not null default 0,
  unit_cost numeric(18,2) not null default 0,
  line_total numeric(18,2) not null default 0,
  line_gross_profit numeric(18,2) not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (sale_id,line_no),
  unique (sale_id,product_id)
);

create index if not exists idx_sale_items_business_sale on public.sale_items(business_id,sale_id,line_no);
create index if not exists idx_sale_items_product on public.sale_items(product_id);

-- Backfill transaksi lama. Trigger stok item BELUM dibuat pada tahap ini,
-- sehingga stok existing tidak terpotong dua kali.
insert into public.sale_items(
  business_id,sale_id,line_no,product_id,product_name,unit,qty,unit_price,unit_cost,line_total,line_gross_profit,created_at,updated_at
)
select s.business_id,s.id,1,s.product_id,s.product_name,coalesce(p.unit,'pcs'),s.qty,s.unit_price,s.unit_cost,
       s.qty*s.unit_price,(s.qty*s.unit_price)-(s.qty*s.unit_cost),s.created_at,coalesce(s.updated_at,s.created_at)
from public.sales s
join public.products p on p.id=s.product_id
where not exists(select 1 from public.sale_items si where si.sale_id=s.id);

alter table public.sale_items enable row level security;
revoke all on table public.sale_items from anon, authenticated;

-- =========================================================
-- 2. Stop legacy one-product stock/financial triggers on sales
-- =========================================================
drop trigger if exists trg_apply_sale_stock on public.sales;
drop trigger if exists trg_prepare_sale_financials on public.sales;

-- Header sales tetap dilindungi dari perubahan field sistem dan paid_amount langsung.
create or replace function public.guard_sale_header_v186()
returns trigger
language plpgsql
security definer
set search_path to pg_catalog, public, auth, extensions
as $$
begin
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
    if coalesce(new.total,0)<0 then raise exception 'Total transaksi tidak valid'; end if;
    if coalesce(old.paid_amount,0)>coalesce(new.total,0)+0.005 then
      raise exception 'Total transaksi baru lebih kecil dari pembayaran yang sudah tercatat';
    end if;
    new.updated_at:=now();
  end if;
  return new;
end;
$$;
revoke all on function public.guard_sale_header_v186() from public,anon,authenticated;
drop trigger if exists trg_guard_sale_header_v186 on public.sales;
create trigger trg_guard_sale_header_v186
before update on public.sales
for each row execute function public.guard_sale_header_v186();

-- =========================================================
-- 3. Sale item pricing + stock protection
-- =========================================================
create or replace function public.prepare_sale_item_v186()
returns trigger
language plpgsql
security definer
set search_path to pg_catalog, public, auth, extensions
as $$
declare
  v_name text;
  v_unit text;
  v_cost numeric;
  v_price numeric;
  v_business uuid;
  v_category text;
  v_stock numeric;
  v_allow_negative boolean:=false;
  v_available numeric;
begin
  if new.qty is null or new.qty<=0 then raise exception 'Qty harus lebih dari 0'; end if;

  if tg_op='UPDATE' then
    if new.id is distinct from old.id
       or new.business_id is distinct from old.business_id
       or new.sale_id is distinct from old.sale_id
       or new.created_at is distinct from old.created_at then
      raise exception 'Field sistem item transaksi tidak boleh diubah';
    end if;
    perform 1 from public.products where id in (old.product_id,new.product_id) order by id for update;
  else
    perform 1 from public.products where id=new.product_id for update;
  end if;

  select p.name,p.unit,p.cost,p.price,p.business_id,p.category,p.stock
    into v_name,v_unit,v_cost,v_price,v_business,v_category,v_stock
  from public.products p where p.id=new.product_id;

  if v_business is null then raise exception 'Produk tidak ditemukan'; end if;
  if v_business<>new.business_id then raise exception 'Produk dan invoice harus berada pada bisnis yang sama'; end if;
  if not exists(select 1 from public.sales s where s.id=new.sale_id and s.business_id=new.business_id) then
    raise exception 'Invoice tidak ditemukan';
  end if;

  select coalesce(b.allow_negative_stock,false) into v_allow_negative from public.businesses b where b.id=new.business_id;
  if v_category<>'Jasa' and not v_allow_negative then
    v_available:=coalesce(v_stock,0);
    if tg_op='UPDATE' and old.product_id=new.product_id then v_available:=v_available+coalesce(old.qty,0); end if;
    if new.qty>v_available then raise exception 'Stok % tidak cukup. Tersedia: %',v_name,v_available; end if;
  end if;

  if tg_op='INSERT' then
    new.product_name:=v_name;
    new.unit:=coalesce(v_unit,'pcs');
    new.unit_price:=coalesce(v_price,0);
    new.unit_cost:=coalesce(v_cost,0);
  elsif new.product_id is distinct from old.product_id then
    new.product_name:=v_name;
    new.unit:=coalesce(v_unit,'pcs');
    new.unit_price:=coalesce(v_price,0);
    new.unit_cost:=coalesce(v_cost,0);
  else
    -- Harga historis tetap terkunci ketika hanya Qty yang diedit.
    new.product_name:=old.product_name;
    new.unit:=old.unit;
    new.unit_price:=old.unit_price;
    new.unit_cost:=old.unit_cost;
  end if;

  new.line_total:=new.qty*new.unit_price;
  new.line_gross_profit:=new.line_total-(new.qty*new.unit_cost);
  new.updated_at:=now();
  return new;
end;
$$;
revoke all on function public.prepare_sale_item_v186() from public,anon,authenticated;
drop trigger if exists trg_prepare_sale_item_v186 on public.sale_items;
create trigger trg_prepare_sale_item_v186
before insert or update on public.sale_items
for each row execute function public.prepare_sale_item_v186();

create or replace function public.apply_sale_item_stock_v186()
returns trigger
language plpgsql
security definer
set search_path to pg_catalog, public, auth, extensions
as $$
begin
  if tg_op='INSERT' then
    update public.products set stock=case when category='Jasa' then stock else stock-new.qty end,updated_at=now() where id=new.product_id;
    return new;
  elsif tg_op='DELETE' then
    update public.products set stock=case when category='Jasa' then stock else stock+old.qty end,updated_at=now() where id=old.product_id;
    return old;
  elsif tg_op='UPDATE' then
    if old.product_id=new.product_id then
      if old.qty is distinct from new.qty then
        update public.products set stock=case when category='Jasa' then stock else stock+old.qty-new.qty end,updated_at=now() where id=new.product_id;
      end if;
    else
      update public.products set stock=case when category='Jasa' then stock else stock+old.qty end,updated_at=now() where id=old.product_id;
      update public.products set stock=case when category='Jasa' then stock else stock-new.qty end,updated_at=now() where id=new.product_id;
    end if;
    return new;
  end if;
  return null;
end;
$$;
revoke all on function public.apply_sale_item_stock_v186() from public,anon,authenticated;
drop trigger if exists trg_apply_sale_item_stock_v186 on public.sale_items;
create trigger trg_apply_sale_item_stock_v186
after insert or update or delete on public.sale_items
for each row execute function public.apply_sale_item_stock_v186();

-- Audit detail item: perubahan Qty/produk terlihat tanpa membanjiri log hanya karena reorder line_no.
create or replace function public.audit_sale_item_v186()
returns trigger
language plpgsql
security definer
set search_path to pg_catalog, public, auth, extensions
as $$
declare v_row jsonb; v_before jsonb; v_after jsonb; v_bid uuid; v_id uuid; v_label text;
begin
  if tg_op='UPDATE' and (to_jsonb(new)-'line_no'-'updated_at')=(to_jsonb(old)-'line_no'-'updated_at') then return null; end if;
  v_bid:=case when tg_op='DELETE' then old.business_id else new.business_id end;
  v_id:=case when tg_op='DELETE' then old.id else new.id end;
  v_before:=case when tg_op in ('UPDATE','DELETE') then to_jsonb(old) else null end;
  v_after:=case when tg_op in ('INSERT','UPDATE') then to_jsonb(new) else null end;
  v_label:='Item · '||coalesce(case when tg_op='DELETE' then old.product_name else new.product_name end,'Produk');
  insert into public.audit_logs(business_id,actor_user_id,actor_email,action,module,record_id,record_label,before_data,after_data,created_at)
  values(v_bid,auth.uid(),coalesce(auth.jwt()->>'email','system'),case tg_op when 'INSERT' then 'CREATE' when 'UPDATE' then 'UPDATE' else 'DELETE' end,'sales',v_id,v_label,v_before,v_after,now());
  return null;
end;
$$;
revoke all on function public.audit_sale_item_v186() from public,anon,authenticated;
drop trigger if exists trg_audit_sale_item_v186 on public.sale_items;
create trigger trg_audit_sale_item_v186
after insert or update or delete on public.sale_items
for each row execute function public.audit_sale_item_v186();

-- =========================================================
-- 4. Role-filtered item read RPC
-- =========================================================
drop function if exists public.list_sale_items_for_business(uuid);
create function public.list_sale_items_for_business(p_bid uuid)
returns table(
  id uuid,business_id uuid,sale_id uuid,line_no integer,product_id uuid,product_name text,unit text,qty numeric,
  unit_price numeric,unit_cost numeric,line_total numeric,line_gross_profit numeric,created_at timestamptz,updated_at timestamptz
)
language plpgsql
security definer
stable
set search_path to pg_catalog, public, auth, extensions
as $$
declare v_role text;
begin
  v_role:=public.business_role(p_bid);
  if v_role not in ('owner','admin','cashier','finance','warehouse') then raise exception 'Tidak memiliki akses penjualan'; end if;
  return query
  select si.id,si.business_id,si.sale_id,si.line_no,si.product_id,si.product_name,si.unit,si.qty,
         case when v_role='warehouse' then null else si.unit_price end,
         case when v_role in ('owner','admin','finance') then si.unit_cost else null end,
         case when v_role='warehouse' then null else si.line_total end,
         case when v_role in ('owner','admin','finance') then si.line_gross_profit else null end,
         si.created_at,si.updated_at
  from public.sale_items si where si.business_id=p_bid order by si.sale_id,si.line_no;
end;
$$;
revoke all on function public.list_sale_items_for_business(uuid) from public,anon;
grant execute on function public.list_sale_items_for_business(uuid) to authenticated;

-- =========================================================
-- 5. Multi-item create RPC
-- =========================================================
drop function if exists public.create_sale_with_items(uuid,date,text,text,text,text,jsonb,numeric,text,numeric,uuid);
create function public.create_sale_with_items(
  p_bid uuid,
  p_sale_date date,
  p_customer_name text,
  p_customer_phone text,
  p_customer_address text,
  p_sale_notes text,
  p_items jsonb,
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
  v_request_id uuid:=coalesce(p_request_id,gen_random_uuid());
  v_existing public.sales%rowtype;
  v_sale public.sales%rowtype;
  v_payment public.payments%rowtype;
  v_inv text; v_sj text; v_kwt text;
  v_count integer; v_matched integer;
  v_first_product uuid; v_first_name text; v_first_price numeric; v_first_cost numeric;
  v_total_qty numeric; v_subtotal numeric; v_cost_total numeric; v_total numeric; v_gp numeric;
  v_item record;
begin
  v_role:=public.business_role(p_bid);
  if v_role not in ('owner','admin','cashier') then raise exception 'Role tidak boleh membuat penjualan'; end if;
  if p_items is null or jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 then raise exception 'Minimal satu item diperlukan'; end if;
  if jsonb_array_length(p_items)>100 then raise exception 'Maksimal 100 jenis item per invoice'; end if;

  select * into v_existing from public.sales x where x.business_id=p_bid and x.client_request_id=v_request_id limit 1;
  if v_existing.id is not null then return jsonb_build_object('ok',true,'duplicate',true,'sale_id',v_existing.id,'invoice_no',v_existing.invoice_no); end if;

  if exists(
    select 1 from (
      select (e.value->>'product_id')::uuid pid,count(*) c
      from jsonb_array_elements(p_items) e(value)
      group by (e.value->>'product_id')::uuid having count(*)>1
    ) d
  ) then raise exception 'Produk yang sama tidak boleh muncul lebih dari satu baris'; end if;

  -- Lock seluruh produk cart dengan urutan deterministic agar harga/stok konsisten selama transaksi.
  perform 1 from public.products p
  where p.id in (select (e.value->>'product_id')::uuid from jsonb_array_elements(p_items) e(value))
  order by p.id for update;

  select count(*),count(p.id),sum((e.value->>'qty')::numeric),sum((e.value->>'qty')::numeric*p.price),sum((e.value->>'qty')::numeric*p.cost)
    into v_count,v_matched,v_total_qty,v_subtotal,v_cost_total
  from jsonb_array_elements(p_items) e(value)
  left join public.products p on p.id=(e.value->>'product_id')::uuid and p.business_id=p_bid;
  if v_count<>v_matched then raise exception 'Ada produk yang tidak ditemukan / bukan milik bisnis'; end if;
  if exists(select 1 from jsonb_array_elements(p_items) e(value) where coalesce((e.value->>'qty')::numeric,0)<=0) then raise exception 'Qty setiap item harus lebih dari 0'; end if;

  select p.id,p.name,p.price,p.cost into v_first_product,v_first_name,v_first_price,v_first_cost
  from jsonb_array_elements(p_items) with ordinality e(value,ord)
  join public.products p on p.id=(e.value->>'product_id')::uuid and p.business_id=p_bid
  order by e.ord limit 1;

  v_total:=greatest(coalesce(v_subtotal,0)-greatest(coalesce(p_discount,0),0),0);
  v_gp:=v_total-coalesce(v_cost_total,0);
  if coalesce(p_initial_paid,0)>v_total+0.005 then raise exception 'Pembayaran awal melebihi total invoice'; end if;

  v_inv:=public.next_document_number(p_bid,'INV',coalesce(p_sale_date,current_date));
  v_sj:=public.next_document_number(p_bid,'SJ',coalesce(p_sale_date,current_date));

  insert into public.sales(
    business_id,date,invoice_no,delivery_no,customer,customer_phone,customer_address,notes,
    product_id,product_name,qty,unit_price,unit_cost,discount,total,gross_profit,payment_method,paid_amount,client_request_id
  ) values (
    p_bid,coalesce(p_sale_date,current_date),v_inv,v_sj,p_customer_name,p_customer_phone,p_customer_address,p_sale_notes,
    v_first_product,case when v_count=1 then v_first_name else v_first_name||' +'||(v_count-1)::text||' item' end,
    v_total_qty,v_first_price,v_first_cost,greatest(coalesce(p_discount,0),0),v_total,v_gp,
    coalesce(nullif(p_payment_method,''),'Cash'),0,v_request_id
  ) returning * into v_sale;

  for v_item in select e.value,e.ord from jsonb_array_elements(p_items) with ordinality e(value,ord) order by e.ord loop
    insert into public.sale_items(business_id,sale_id,line_no,product_id,product_name,unit,qty,unit_price,unit_cost,line_total,line_gross_profit)
    values(p_bid,v_sale.id,v_item.ord,(v_item.value->>'product_id')::uuid,'','pcs',(v_item.value->>'qty')::numeric,0,0,0,0);
  end loop;

  if coalesce(p_initial_paid,0)>0 then
    v_kwt:=public.next_document_number(p_bid,'KWT',coalesce(p_sale_date,current_date));
    insert into public.payments(business_id,sale_id,payment_no,payment_date,amount,method,notes,receipt_no,client_request_id,created_by)
    values(p_bid,v_sale.id,0,coalesce(p_sale_date,current_date),p_initial_paid,coalesce(nullif(p_payment_method,''),'Cash'),'Pembayaran awal',v_kwt,v_request_id,auth.uid())
    returning * into v_payment;
  end if;

  return jsonb_build_object('ok',true,'duplicate',false,'sale_id',v_sale.id,'invoice_no',v_sale.invoice_no,'delivery_no',v_sale.delivery_no,'payment_id',v_payment.id);
end;
$$;
revoke all on function public.create_sale_with_items(uuid,date,text,text,text,text,jsonb,numeric,text,numeric,uuid) from public,anon;
grant execute on function public.create_sale_with_items(uuid,date,text,text,text,text,jsonb,numeric,text,numeric,uuid) to authenticated;

-- =========================================================
-- 6. Multi-item update RPC
-- =========================================================
drop function if exists public.update_sale_with_items(uuid,uuid,date,text,text,text,text,jsonb,numeric,text);
create function public.update_sale_with_items(
  p_bid uuid,
  p_sale_id uuid,
  p_sale_date date,
  p_customer_name text,
  p_customer_phone text,
  p_customer_address text,
  p_sale_notes text,
  p_items jsonb,
  p_discount numeric,
  p_payment_method text
)
returns jsonb
language plpgsql
security definer
set search_path to pg_catalog, public, auth, extensions
as $$
declare
  v_role text; v_sale public.sales%rowtype; v_item record;
  v_count integer; v_first public.sale_items%rowtype;
  v_total_qty numeric; v_subtotal numeric; v_cost_total numeric; v_total numeric; v_gp numeric;
begin
  v_role:=public.business_role(p_bid);
  if v_role not in ('owner','admin','cashier') then raise exception 'Role tidak boleh mengubah penjualan'; end if;
  if p_items is null or jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 then raise exception 'Minimal satu item diperlukan'; end if;
  if jsonb_array_length(p_items)>100 then raise exception 'Maksimal 100 jenis item per invoice'; end if;

  select * into v_sale from public.sales s where s.id=p_sale_id and s.business_id=p_bid for update;
  if v_sale.id is null then raise exception 'Transaksi tidak ditemukan'; end if;

  if exists(
    select 1 from (
      select (e.value->>'product_id')::uuid pid,count(*) c
      from jsonb_array_elements(p_items) e(value)
      group by (e.value->>'product_id')::uuid having count(*)>1
    ) d
  ) then raise exception 'Produk yang sama tidak boleh muncul lebih dari satu baris'; end if;
  if exists(select 1 from jsonb_array_elements(p_items) e(value) where coalesce((e.value->>'qty')::numeric,0)<=0) then raise exception 'Qty setiap item harus lebih dari 0'; end if;
  if exists(select 1 from jsonb_array_elements(p_items) e(value) left join public.products p on p.id=(e.value->>'product_id')::uuid and p.business_id=p_bid where p.id is null) then raise exception 'Ada produk yang tidak ditemukan / bukan milik bisnis'; end if;

  -- Geser nomor baris sementara supaya reorder (1↔2) tidak menabrak unique(sale_id,line_no).
  update public.sale_items set line_no=line_no+1000 where sale_id=p_sale_id and business_id=p_bid;

  -- Hapus item yang tidak lagi ada; AFTER DELETE mengembalikan stoknya.
  delete from public.sale_items si
  where si.sale_id=p_sale_id and si.business_id=p_bid
    and not exists(select 1 from jsonb_array_elements(p_items) e(value) where (e.value->>'product_id')::uuid=si.product_id);

  -- Update item existing agar harga historis tetap terkunci; insert item baru memakai harga master saat ini.
  for v_item in select e.value,e.ord from jsonb_array_elements(p_items) with ordinality e(value,ord) order by e.ord loop
    if exists(select 1 from public.sale_items si where si.sale_id=p_sale_id and si.product_id=(v_item.value->>'product_id')::uuid) then
      update public.sale_items si set line_no=v_item.ord,qty=(v_item.value->>'qty')::numeric
      where si.sale_id=p_sale_id and si.product_id=(v_item.value->>'product_id')::uuid;
    else
      insert into public.sale_items(business_id,sale_id,line_no,product_id,product_name,unit,qty,unit_price,unit_cost,line_total,line_gross_profit)
      values(p_bid,p_sale_id,v_item.ord,(v_item.value->>'product_id')::uuid,'','pcs',(v_item.value->>'qty')::numeric,0,0,0,0);
    end if;
  end loop;

  select count(*),sum(qty),sum(line_total),sum(qty*unit_cost)
    into v_count,v_total_qty,v_subtotal,v_cost_total
  from public.sale_items where sale_id=p_sale_id;
  select * into v_first from public.sale_items where sale_id=p_sale_id order by line_no limit 1;
  v_total:=greatest(coalesce(v_subtotal,0)-greatest(coalesce(p_discount,0),0),0);
  v_gp:=v_total-coalesce(v_cost_total,0);
  if coalesce(v_sale.paid_amount,0)>v_total+0.005 then raise exception 'Total transaksi baru lebih kecil dari pembayaran yang sudah tercatat'; end if;

  update public.sales s set
    date=coalesce(p_sale_date,s.date),customer=p_customer_name,customer_phone=p_customer_phone,
    customer_address=p_customer_address,notes=p_sale_notes,
    product_id=v_first.product_id,
    product_name=case when v_count=1 then v_first.product_name else v_first.product_name||' +'||(v_count-1)::text||' item' end,
    qty=v_total_qty,unit_price=v_first.unit_price,unit_cost=v_first.unit_cost,
    discount=greatest(coalesce(p_discount,0),0),total=v_total,gross_profit=v_gp,
    payment_method=coalesce(nullif(p_payment_method,''),s.payment_method)
  where s.id=p_sale_id and s.business_id=p_bid
  returning * into v_sale;

  return jsonb_build_object('ok',true,'sale_id',v_sale.id,'invoice_no',v_sale.invoice_no);
end;
$$;
revoke all on function public.update_sale_with_items(uuid,uuid,date,text,text,text,text,jsonb,numeric,text) from public,anon;
grant execute on function public.update_sale_with_items(uuid,uuid,date,text,text,text,text,jsonb,numeric,text) to authenticated;

-- =========================================================
-- 7. Backward-compatible legacy single-item RPCs
-- =========================================================
create or replace function public.create_sale_with_payment(
  p_bid uuid,p_sale_date date,p_customer_name text,p_customer_phone text,p_customer_address text,p_sale_notes text,
  p_product_id uuid,p_qty numeric,p_discount numeric,p_payment_method text,p_initial_paid numeric default 0,p_request_id uuid default null
)
returns jsonb language plpgsql security definer
set search_path to pg_catalog, public, auth, extensions
as $$
begin
  return public.create_sale_with_items(p_bid,p_sale_date,p_customer_name,p_customer_phone,p_customer_address,p_sale_notes,
    jsonb_build_array(jsonb_build_object('product_id',p_product_id,'qty',p_qty)),p_discount,p_payment_method,p_initial_paid,p_request_id);
end;
$$;

create or replace function public.update_sale_secure(
  p_bid uuid,p_sale_id uuid,p_sale_date date,p_customer_name text,p_customer_phone text,p_customer_address text,p_sale_notes text,
  p_product_id uuid,p_qty numeric,p_discount numeric,p_payment_method text
)
returns jsonb language plpgsql security definer
set search_path to pg_catalog, public, auth, extensions
as $$
begin
  return public.update_sale_with_items(p_bid,p_sale_id,p_sale_date,p_customer_name,p_customer_phone,p_customer_address,p_sale_notes,
    jsonb_build_array(jsonb_build_object('product_id',p_product_id,'qty',p_qty)),p_discount,p_payment_method);
end;
$$;
revoke all on function public.create_sale_with_payment(uuid,date,text,text,text,text,uuid,numeric,numeric,text,numeric,uuid) from public,anon;
grant execute on function public.create_sale_with_payment(uuid,date,text,text,text,text,uuid,numeric,numeric,text,numeric,uuid) to authenticated;
revoke all on function public.update_sale_secure(uuid,uuid,date,text,text,text,text,uuid,numeric,numeric,text) from public,anon;
grant execute on function public.update_sale_secure(uuid,uuid,date,text,text,text,text,uuid,numeric,numeric,text) to authenticated;

-- =========================================================
-- 8. Product-history protection for items not in header summary
-- =========================================================
create or replace function public.secure_delete_record_v2(p_bid uuid, p_entity text, p_record_id uuid, p_pin text)
returns jsonb
language plpgsql
security definer
set search_path to pg_catalog, public, auth, extensions
as $$
declare
  v_stored_hash text; v_att public.security_key_attempts%rowtype; v_new_count integer; v_lock_until timestamptz;
  v_affected integer:=0; v_sale_id uuid;
begin
  if auth.uid() is null or not public.has_business_role(p_bid,array['owner','admin']) then raise exception 'Hanya owner/admin yang dapat menghapus data permanen'; end if;
  if p_pin !~ '^[0-9]{6}$' then return jsonb_build_object('ok',false,'error','Security Key harus 6 digit'); end if;
  insert into public.security_key_attempts(business_id,user_id,failed_attempts,updated_at)
  values(p_bid,auth.uid(),0,now()) on conflict(business_id,user_id) do nothing;
  select * into v_att from public.security_key_attempts where business_id=p_bid and user_id=auth.uid() for update;
  if v_att.locked_until is not null and v_att.locked_until>now() then return jsonb_build_object('ok',false,'error','Security Key terkunci sementara','locked_until',v_att.locked_until); end if;
  select delete_pin_hash into v_stored_hash from public.business_security where business_id=p_bid;
  if v_stored_hash is null then return jsonb_build_object('ok',false,'error','Security Key belum diatur'); end if;
  if crypt(p_pin,v_stored_hash)<>v_stored_hash then
    v_new_count:=coalesce(v_att.failed_attempts,0)+1;v_lock_until:=case when v_new_count>=5 then now()+interval '15 minutes' else null end;
    update public.security_key_attempts set failed_attempts=case when v_new_count>=5 then 0 else v_new_count end,locked_until=v_lock_until,last_failed_at=now(),updated_at=now()
    where business_id=p_bid and user_id=auth.uid();
    return jsonb_build_object('ok',false,'error',case when v_lock_until is not null then 'Terlalu banyak percobaan. Security Key dikunci 15 menit.' else 'Security Key salah' end,'remaining_attempts',greatest(5-v_new_count,0),'locked_until',v_lock_until);
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
    if exists(select 1 from public.sale_items si where si.business_id=p_bid and si.product_id=p_record_id)
       or exists(select 1 from public.sales s where s.business_id=p_bid and s.product_id=p_record_id) then
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

commit;
