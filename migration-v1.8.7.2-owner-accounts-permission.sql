-- BizControl V1.8.7.2 — owner_accounts service-role permission hotfix
-- Fixes: permission denied for table owner_accounts from account-admin Edge Function.
-- Safe for staging/production: grants access ONLY to trusted server role, not anon/authenticated.

begin;

grant usage on schema public to service_role;

grant select, insert, update, delete
  on table public.owner_accounts
  to service_role;

-- Explicit privileges used by account-admin so future default-privilege hardening
-- cannot break server-side Owner/member administration.
grant select
  on table public.businesses, public.business_members
  to service_role;

grant select, insert
  on table public.audit_logs
  to service_role;

-- Browser roles remain blocked from owner_accounts.
revoke all
  on table public.owner_accounts
  from public, anon, authenticated;

notify pgrst, 'reload schema';

commit;

-- Verification:
select
  has_table_privilege('service_role','public.owner_accounts','SELECT') as service_can_select,
  has_table_privilege('service_role','public.owner_accounts','INSERT') as service_can_insert,
  has_table_privilege('service_role','public.owner_accounts','UPDATE') as service_can_update,
  has_table_privilege('authenticated','public.owner_accounts','SELECT') as browser_can_select;
-- Expected: true, true, true, false
