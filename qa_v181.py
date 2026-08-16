from pathlib import Path
import re, subprocess, sys, json
base=Path(__file__).parent
app=(base/'app.js').read_text()
idx=(base/'index.html').read_text()
css=(base/'styles.css').read_text()
sql=(base/'supabase-schema-v1.8.1.sql').read_text()
mig=(base/'migration-v1.8.1-production-patch.sql').read_text()
sw=(base/'sw.js').read_text()
headers=(base/'_headers').read_text()
checks=[]
def check(name,cond): checks.append((name,bool(cond)))
def last_func(name):
    marker=f'create or replace function public.{name}'
    pos=sql.lower().rfind(marker.lower())
    if pos<0:return ''
    nxt=sql.lower().find('create or replace function public.',pos+len(marker))
    if nxt<0:nxt=len(sql)
    return sql[pos:nxt]

# JS syntax
r=subprocess.run(['node','--check',str(base/'app.js')],capture_output=True,text=True)
check('JavaScript syntax valid',r.returncode==0)
check('Version label V1.8.1', 'V1.8.1 Production Patch' in app and 'ONLINE V1.8.1' in idx)
check('Forgot password control exists', 'forgotPasswordBtn' in idx and 'sendPasswordRecovery' in app)
check('Recovery endpoint used', "/auth/v1/recover?redirect_to=" in app)
check('Recovery response avoids user enumeration', 'Jika email terdaftar' in app)
check('Recovery link parses type=recovery', "hash.get('type')!=='recovery'" in app)
check('Password update endpoint used', "'/auth/v1/user'" in app and "method:'PUT'" in app)
check('Recovery requires re-login', "clearSession();history.replaceState" in app and 'Silakan login dengan password baru' in app)
check('Password minimum 8', 'minlength="8"' in idx and "length<8" in app)
check('Runtime production config supported', 'window.BIZCONTROL_CONFIG' in app and (base/'runtime-config.js').exists())
check('Runtime config has no service-role field', 'serviceRole' not in (base/'runtime-config.js').read_text() and 'secretKey' not in (base/'runtime-config.js').read_text())
check('Cloud sessions use sessionStorage', "sessionStorage.getItem('bc_session')" in app and "sessionStorage.setItem('bc_session'" in app)
check('Legacy localStorage session is removed', "localStorage.removeItem('bc_session')" in app)
check('Service worker cache version bumped', 'bizcontrol-v1-8-1-production-patch' in sw)
check('Service worker includes runtime config', 'runtime-config.js' in sw)
check('Runtime config no-store header', '/runtime-config.js' in headers and 'no-store' in headers)
check('CSP frame ancestors HTTP header', "frame-ancestors 'none'" in headers)

# SQL security patch
for needle,name in [
    ('revoke create on schema public from public, anon, authenticated','Public schema CREATE revoked'),
    ('alter default privileges for role postgres in schema public','Default privileges hardened'),
    ('revoke select, insert, update, delete on tables from anon, authenticated, service_role','Future table grants revoked'),
    ('revoke execute on functions from anon, authenticated, service_role','Future function grants revoked'),
    ('revoke usage, select on sequences from anon, authenticated, service_role','Future sequence grants revoked'),
    ('revoke execute on all functions in schema public from public, anon, authenticated','Existing function execute reset'),
]: check(name,needle in mig.lower())

create_block=last_func('create_sale_with_payment')
update_block=last_func('update_sale_secure')
check('Create sale mutation response no to_jsonb(v_sale)', 'to_jsonb(v_sale)' not in create_block)
check('Update sale mutation response no to_jsonb(v_sale)', 'to_jsonb(v_sale)' not in update_block)
# ensure sensitive keys never serialized in response builders in final overrides
create_return_section=create_block[create_block.find('v_sale_json:='):]
update_return_section=update_block[update_block.find('v_sale_json:='):]
check('Create sale response excludes unit_cost key', "'unit_cost'" not in create_return_section)
check('Create sale response excludes gross_profit key', "'gross_profit'" not in create_return_section)
check('Update sale response excludes unit_cost key', "'unit_cost'" not in update_return_section)
check('Update sale response excludes gross_profit key', "'gross_profit'" not in update_return_section)

list_block=last_func('list_sales_for_business')
check('Cashier list cannot read unit_cost', "case when r in ('owner','admin','finance') then s.unit_cost else null end" in list_block)
check('Cashier list cannot read gross_profit', "case when r in ('owner','admin','finance') then s.gross_profit else null end" in list_block)
check('Warehouse price hidden', "case when r='warehouse' then null else s.unit_price end" in list_block)
check('Warehouse payment hidden', "case when r='warehouse' then null else s.paid_amount end" in list_block)

# High-impact functions get fixed trusted search path and only production RPCs regranted.
for fn_sig in [
    'business_role(uuid)','has_business_role(uuid,text[])','can_access_business(uuid)','has_delete_pin(uuid)',
    'list_products_for_business(uuid)','list_sales_for_business(uuid)','list_business_members(uuid)',
    'create_sale_with_payment(uuid,date,text,text,text,text,uuid,numeric,numeric,text,numeric,uuid)',
    'update_sale_secure(uuid,uuid,date,text,text,text,text,uuid,numeric,numeric,text)',
    'record_payment(uuid,uuid,uuid,date,numeric,text,text,uuid)','set_delete_pin_v2(uuid,text,text)',
    'secure_delete_record_v2(uuid,text,uuid,text)']:
    check('Explicit EXECUTE '+fn_sig, f'grant execute on function public.{fn_sig} to authenticated' in mig.lower())

check('Legacy delete RPC remains revoked', 'revoke execute on function public.secure_delete_record(uuid,text,uuid,text) from public,anon,authenticated' in mig.lower())
check('Document sequence RPC not browser callable', 'revoke execute on function public.next_document_number(uuid,text,date) from public,anon,authenticated' in mig.lower())
check('SECURITY DEFINER trusted path applied', 'set search_path to pg_catalog, public, auth, extensions' in mig.lower())

# Existing UI safety/regression signals
check('escapeHtml helper exists', 'function escapeHtml' in app)
check('No floating Supabase CDN SDK', '@supabase/supabase-js@2' not in idx+app)
check('Mobile responsive card CSS retained', '@media(max-width:760px)' in css and 'table.responsive-table' in css and 'data-mobile-type="sales"' in css)
check('Security key lockout retained', 'set_delete_pin_v2' in app and 'secure_delete_record_v2' in app)
check('Atomic sale RPC retained', '/rest/v1/rpc/create_sale_with_payment' in app)
check('Atomic payment RPC retained', '/rest/v1/rpc/record_payment' in app)

passed=sum(v for _,v in checks)
print(f'{passed}/{len(checks)} PASS')
for name,ok in checks:
    print(('PASS' if ok else 'FAIL')+' | '+name)
if passed!=len(checks):sys.exit(1)
