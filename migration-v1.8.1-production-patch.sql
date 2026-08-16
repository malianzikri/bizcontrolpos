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
