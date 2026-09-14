-- BizControl V1.9 Purchasing: suppliers, PO, item receipt, supplier payable
create table if not exists public.suppliers (
  id uuid primary key default gen_random_uuid(), business_id uuid not null references public.businesses(id) on delete cascade,
  name text not null, client_request_id uuid, contact_person text, phone text, email text, address text, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists public.purchase_orders (
  id uuid primary key default gen_random_uuid(), business_id uuid not null references public.businesses(id) on delete cascade,
  po_no text not null, supplier_id uuid not null references public.suppliers(id), order_date date not null default current_date,
  notes text, total_amount numeric(18,2) not null default 0, paid_amount numeric(18,2) not null default 0,
  status text not null default 'ordered' check(status in ('draft','ordered','partial','completed','cancelled')),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), unique(business_id,po_no)
);
create table if not exists public.purchase_order_items (
  id uuid primary key default gen_random_uuid(), business_id uuid not null references public.businesses(id) on delete cascade,
  purchase_order_id uuid not null references public.purchase_orders(id) on delete cascade, line_no int not null,
  product_id uuid not null references public.products(id), product_name text not null, unit text,
  qty numeric(18,3) not null check(qty>0), unit_cost numeric(18,2) not null default 0,
  line_total numeric(18,2) not null default 0, received_qty numeric(18,3) not null default 0,
  created_at timestamptz not null default now(), unique(purchase_order_id,line_no)
);
create unique index if not exists suppliers_request_uidx on public.suppliers(business_id,client_request_id) where client_request_id is not null;
alter table public.suppliers enable row level security; alter table public.purchase_orders enable row level security; alter table public.purchase_order_items enable row level security;
drop policy if exists "suppliers view" on public.suppliers; create policy "suppliers view" on public.suppliers for select using(public.has_business_role(business_id,array['owner','admin','finance','warehouse']));
drop policy if exists "suppliers manage" on public.suppliers; create policy "suppliers manage" on public.suppliers for all using(public.has_business_role(business_id,array['owner','admin','finance'])) with check(public.has_business_role(business_id,array['owner','admin','finance']));
drop policy if exists "po view" on public.purchase_orders; create policy "po view" on public.purchase_orders for select using(public.has_business_role(business_id,array['owner','admin','finance','warehouse']));
drop policy if exists "po manage" on public.purchase_orders; create policy "po manage" on public.purchase_orders for all using(public.has_business_role(business_id,array['owner','admin','finance'])) with check(public.has_business_role(business_id,array['owner','admin','finance']));
drop policy if exists "po items view" on public.purchase_order_items; create policy "po items view" on public.purchase_order_items for select using(public.has_business_role(business_id,array['owner','admin','finance','warehouse']));
drop policy if exists "po items manage" on public.purchase_order_items; create policy "po items manage" on public.purchase_order_items for all using(public.has_business_role(business_id,array['owner','admin','finance'])) with check(public.has_business_role(business_id,array['owner','admin','finance']));

create or replace function public.create_purchase_order(p_bid uuid,p_supplier_id uuid,p_order_date date,p_notes text,p_paid_amount numeric,p_items jsonb) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_id uuid:=gen_random_uuid(); v_no text; v_total numeric:=0; r jsonb; p public.products%rowtype; n int:=0;
begin
 if not public.has_business_role(p_bid,array['owner','admin','finance']) then return jsonb_build_object('ok',false,'error','Tidak diizinkan'); end if;
 select 'PO-'||to_char(current_date,'YYYY')||'-'||lpad((count(*)+1)::text,4,'0') into v_no from public.purchase_orders where business_id=p_bid;
 for r in select * from jsonb_array_elements(p_items) loop
  select * into p from public.products where id=(r->>'product_id')::uuid and business_id=p_bid; if not found then raise exception 'Produk tidak ditemukan'; end if;
  v_total:=v_total+((r->>'qty')::numeric*(r->>'unit_cost')::numeric);
 end loop;
 insert into public.purchase_orders(id,business_id,po_no,supplier_id,order_date,notes,total_amount,paid_amount,status) values(v_id,p_bid,v_no,p_supplier_id,p_order_date,p_notes,v_total,least(greatest(coalesce(p_paid_amount,0),0),v_total),'ordered');
 for r in select * from jsonb_array_elements(p_items) loop n:=n+1; select * into p from public.products where id=(r->>'product_id')::uuid;
  insert into public.purchase_order_items(business_id,purchase_order_id,line_no,product_id,product_name,unit,qty,unit_cost,line_total) values(p_bid,v_id,n,p.id,p.name,p.unit,(r->>'qty')::numeric,(r->>'unit_cost')::numeric,(r->>'qty')::numeric*(r->>'unit_cost')::numeric); end loop;
 return jsonb_build_object('ok',true,'id',v_id,'po_no',v_no);
end $$;
grant execute on function public.create_purchase_order(uuid,uuid,date,text,numeric,jsonb) to authenticated;

create or replace function public.receive_purchase_order(p_bid uuid,p_po_id uuid,p_received jsonb) returns jsonb language plpgsql security definer set search_path=public as $$
declare r jsonb; it public.purchase_order_items%rowtype; q numeric; complete boolean;
begin
 if not public.has_business_role(p_bid,array['owner','admin','finance','warehouse']) then return jsonb_build_object('ok',false,'error','Tidak diizinkan'); end if;
 for r in select * from jsonb_array_elements(p_received) loop
  select * into it from public.purchase_order_items where id=(r->>'item_id')::uuid and purchase_order_id=p_po_id and business_id=p_bid for update;
  if found then q:=least(greatest((r->>'qty')::numeric,0),greatest(it.qty-it.received_qty,0)); if q>0 then
   update public.purchase_order_items set received_qty=received_qty+q where id=it.id;
   update public.products set stock=coalesce(stock,0)+q,cost=it.unit_cost where id=it.product_id and business_id=p_bid;
  end if; end if;
 end loop;
 select bool_and(received_qty>=qty) into complete from public.purchase_order_items where purchase_order_id=p_po_id;
 update public.purchase_orders set status=case when complete then 'completed' else 'partial' end,updated_at=now() where id=p_po_id and business_id=p_bid;
 return jsonb_build_object('ok',true,'status',case when complete then 'completed' else 'partial' end);
end $$;
grant execute on function public.receive_purchase_order(uuid,uuid,jsonb) to authenticated;
