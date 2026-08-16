# BizControl Online V1.8 — Static Security QA

**Result: 35/35 PASS**

- PASS — JavaScript syntax (node --check)
- PASS — No Supabase JS global/CDN dependency
- PASS — Cloud session stored in sessionStorage
- PASS — Legacy localStorage session migrated then removed
- PASS — Dashboard business name escaped
- PASS — Password minimum 8
- PASS — Turnstile integration ready
- PASS — CSP present
- PASS — Production security headers present
- PASS — Service worker never caches cross-origin responses
- PASS — Service worker only caches explicit static names
- PASS — Service worker cache bumped
- PASS — Atomic sale RPC used by frontend
- PASS — Secure sale update RPC used by frontend
- PASS — Atomic payment RPC used by frontend
- PASS — Atomic sale RPC exists in SQL
- PASS — Payment row-lock exists
- PASS — Security Key V2 used by frontend
- PASS — Security Key rate limiting
- PASS — Legacy Security Key RPC execution revoked
- PASS — Business ownership immutable
- PASS — Negative stock disabled by default
- PASS — Warehouse sales financials masked
- PASS — Warehouse product selling price masked
- PASS — Warehouse product HPP restricted
- PASS — No direct sales table grant
- PASS — Payments have no direct mutation grant
- PASS — Product direct SELECT limited to identity/request columns
- PASS — Document number RPC hidden from browser
- PASS — Migration transaction wrapper
- PASS — Dollar quote delimiters balanced
- PASS — Fresh schema includes V1.8 hardening
- PASS — Demo mode warns against production data
- PASS — Warehouse print UI excludes Invoice/Kwitansi
- PASS — V1.8 version visible

## Real-browser regression

- Chromium suite A: **27/27 PASS**.
- Chromium suite B: **8/8 PASS**.
- Combined real-browser checks: **35/35 PASS**.

## Scope limitation

- This QA validates source patterns, JavaScript syntax, browser behavior, and security configuration files.
- It does **not** execute the PostgreSQL migration against a live Supabase/Postgres project.
- Apply V1.8 to a staging Supabase project and perform real role/concurrency tests before public launch.
