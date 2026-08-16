# BizControl V1.8.5 Final UX QA

Checks:
- Owner settings contain no editable Supabase URL/key fields.
- `openCloudSettings` removed.
- `loadCloudConfig()` reads runtime config only.
- Legacy browser `bc_cloud_config` removed during boot.
- No-session boot opens account landing.
- Demo is one-click and does not authenticate.
- Demo sidebar/settings provide Masuk/Daftar path.
- Demo can be reset to seeded simulation data.
- Logout returns to account landing.
- Cloud session still boots directly when valid session exists.
- Service worker cache bumped to V1.8.5.
