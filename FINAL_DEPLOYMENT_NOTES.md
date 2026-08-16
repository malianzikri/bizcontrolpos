# BizControl Online V1.8.5 — Final Deployment Notes

## What changed

1. Cloud/Supabase configuration is deployment-managed only. Owner has no UI to view or change Project URL, Publishable Key, or Turnstile Site Key.
2. Legacy `bc_cloud_config` browser storage is deleted on boot.
3. First visit without an authenticated session opens the Login/Daftar landing page.
4. `Coba Demo Gratis` opens the local demo sandbox without authentication. Demo data never writes to Supabase.
5. Demo has a visible path back to `Masuk / Daftar` and a `Reset Data Demo` control.
6. Logout returns to the account landing instead of silently entering demo.

## Staging upgrade

No database migration is required from V1.8.4.1. Keep the existing V1.8.4 Team Invitation migration, document-number hotfix, and `team-invite` Edge Function already deployed.

Copy your existing deployment values into `runtime-config.js`:

```js
window.BIZCONTROL_CONFIG = {
  supabaseUrl: 'https://YOUR_PROJECT.supabase.co',
  publishableKey: 'sb_publishable_...',
  turnstileSiteKey: ''
};
```

Never place a Supabase secret/service-role key in frontend files. The publishable key is intentionally browser-visible; access control must remain enforced by RLS/RPC.
