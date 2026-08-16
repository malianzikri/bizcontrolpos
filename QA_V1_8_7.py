from pathlib import Path
import re, subprocess, json, sys
root=Path(__file__).parent
app=(root/'app.js').read_text()
html=(root/'index.html').read_text()
css=(root/'styles.css').read_text()
sql=(root/'migration-v1.8.7-invite-only-access.sql').read_text()
ts=(root/'account-admin-edge-function.ts').read_text()
config=(root/'runtime-config.js').read_text()
sw=(root/'sw.js').read_text()
checks=[]
def check(name, cond): checks.append((name,bool(cond)))

# Public / demo UX
check('public signup tab removed', 'authSignupTab' not in html and 'authSignupTab' not in app)
check('public signup endpoint removed', '/auth/v1/signup' not in app)
check('chat admin CTA exists', 'contactAdminBtn' in html and 'contactSystemAdmin' in app)
check('demo mobile login button exists', 'demoLoginBtn' in html and '#demoLoginBtn' in app)
check('demo mobile login forced visible CSS', '#demoLoginBtn:not(.hidden)' in css)
check('cloud account button available mobile', 'accountSettingsBtn' in html and '#accountSettingsBtn:not(.hidden)' in css)
check('support WhatsApp deployment config', 'supportWhatsApp' in config)

# Password features
check('self change password UI', 'change-password' in app and 'openChangePasswordModal' in app)
check('self password update endpoint', "'/auth/v1/user'" in app and "method:'PUT'" in app)
check('member reset button', 'reset-member-password' in app)
check('owner reset member edge action', "invokeAccountAdmin('reset-member'" in app)
check('system admin owner reset UI', 'reset-owner-password' in app and 'Kirim Reset Password' in app)
check('recovery link flow retained', '/auth/v1/recover' in app and "['recovery','invite']" in app)

# System admin / invite-only authorization
check('system admin nav server-gated state', "n.id==='systemAdmin'?(state.mode==='cloud'&&state.isSystemAdmin)" in app)
check('system admin status from edge function', "invokeAccountAdmin('status')" in app)
check('system admin owner invite', "invokeAccountAdmin('invite-owner'" in app)
check('owner_accounts table', 'create table if not exists public.owner_accounts' in sql)
check('owner_accounts direct browser access revoked', 'revoke all on table public.owner_accounts from public, anon, authenticated' in sql)
check('existing owners backfilled', 'insert into public.owner_accounts' in sql and 'from public.businesses b' in sql)
check('can_create_business RPC', 'function public.can_create_business()' in sql)
check('create_business hardened', 'if not public.can_create_business() then' in sql)
check('frontend trusts server can_create_business', "'/rest/v1/rpc/can_create_business'" in app)
check('old user_metadata owner bootstrap removed', "user_metadata?.bizcontrol_account_type" not in app[app.find('async function cloudBootstrap'):])

# Edge function server-side checks
check('account admin verifies bearer user', 'admin.auth.getUser(token)' in ts)
check('system admin allowlist secret', 'BIZCONTROL_SYSTEM_ADMIN_EMAILS' in ts)
check('allowed redirect secret', 'BIZCONTROL_ALLOWED_REDIRECTS' in ts)
check('invite owner uses admin API', 'admin.auth.admin.inviteUserByEmail' in ts)
check('owner reset uses recovery API', 'admin.auth.resetPasswordForEmail' in ts and "action === 'reset-owner'" in ts)
check('member reset verifies business owner', "business.owner_id !== actor.id" in ts and "action === 'reset-member'" in ts)
check('member reset verifies membership', ".from('business_members')" in ts and "member.status !== 'active'" in ts)
check('member reset audited as SECURITY', "action: 'SECURITY'" in ts and "password_reset_requested" in ts)
check('no service role in runtime config', 'service_role' not in config.lower().replace('never place a supabase service_role/secret key in this file.',''))

# Version/cache
check('app version export 1.8.7', "version:'1.8.7'" in app)
check('service worker cache bumped', 'bizcontrol-v1-8-7-invite-only-access' in sw)
check('fresh schema v1.8.7 exists', (root/'supabase-schema-v1.8.7.sql').exists())

# Syntax
node=subprocess.run(['node','--check',str(root/'app.js')],capture_output=True,text=True)
check('app.js syntax', node.returncode==0)

passed=sum(1 for _,ok in checks if ok)
for name,ok in checks:
    print(('PASS' if ok else 'FAIL')+' | '+name)
print(f'\nRESULT {passed}/{len(checks)} PASS')
if passed!=len(checks): sys.exit(1)
