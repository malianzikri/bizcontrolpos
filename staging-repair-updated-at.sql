-- BizControl staging repair: updated_at compatibility
-- Safe to run after the Fresh Schema stopped with:
-- column "updated_at" of relation "sales" does not exist

begin;

alter table public.sales
  add column if not exists updated_at timestamptz not null default now();

alter table public.expenses
  add column if not exists updated_at timestamptz not null default now();

commit;

-- Verification
select table_name, column_name, data_type
from information_schema.columns
where table_schema='public'
  and table_name in ('sales','expenses')
  and column_name='updated_at'
order by table_name;
