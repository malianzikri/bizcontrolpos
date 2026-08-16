# BizControl V1.8.4 — Team Invitation Setup

## What changed
- Owner invites employees from **Tim & Role** using email + role.
- New email: Supabase sends an invite email; user clicks it, creates a password, then logs in.
- Existing Supabase/BizControl account: access is activated immediately without another registration.
- Owner can change role or **Hapus / Cabut Akses**.
- Removing membership immediately removes database access through RLS. The auth account is not globally deleted, so the same person can still belong to another business safely.
- Invited employee accounts are not allowed to auto-create a new owner business when they have no active membership.

## 1. Run database migration
In Supabase SQL Editor, run:

`migration-v1.8.4-team-invitation.sql`

Expected result: `Success. No rows returned`.

## 2. Deploy Edge Function
The function source is:

`supabase/functions/team-invite/index.ts`

### Easiest: Supabase Dashboard
1. Open **Edge Functions** in the Supabase Dashboard.
2. Create a function named `team-invite`.
3. Paste the content of `supabase/functions/team-invite/index.ts`.
4. Disable gateway JWT verification for this function if the dashboard exposes that option. The function verifies the caller's user access token itself with Supabase Auth.
5. Deploy.

### CLI alternative
From the project source folder:

```bash
supabase login
supabase link --project-ref YOUR_PROJECT_REF
supabase functions deploy team-invite --no-verify-jwt
```

Hosted Edge Functions already receive `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` as environment variables. Never place the service-role key in `runtime-config.js` or browser code.

## 3. Auth redirect URLs
In **Authentication → URL Configuration**, keep your staging/local URL allow-listed, for example:

- `http://localhost:5500/**`
- your future staging URL, e.g. `https://bizcontrol-staging.vercel.app/**`

The invite email redirects back to the exact origin/path used by the Owner when sending the invite.

## 4. Test
1. Login as Owner.
2. Open **Tim & Role**.
3. Click **Undang Anggota**.
4. Enter a new email and choose `Kasir`.
5. Confirm the row shows **Menunggu Undangan**.
6. Open the invite email in an incognito browser/device.
7. Create password, then login.
8. Confirm role is `Kasir` and HPP/owner-only menus are not available.
9. Back as Owner, click **Hapus / Cabut Akses**.
10. Within the next request/poll, the employee can no longer read or modify that business. A fresh login should be refused with “tidak memiliki akses bisnis aktif”.
