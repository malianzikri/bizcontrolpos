# BizControl Online V1.8 — Security Hardening Report

## Status
**Security-hardening source selesai. Status release: staging / closed-beta security validation.**

Tidak ada klaim bahwa aplikasi “100% aman”. V1.8 menutup temuan audit yang diketahui dan menambah defense-in-depth, namun migration masih perlu dijalankan dan diuji pada Supabase staging yang nyata.

## Temuan → Perbaikan

| Temuan audit | Severity | Perbaikan V1.8 | Status source |
|---|---|---|---|
| Stored XSS nama bisnis / output dinamis | Critical | Escape output + CSP + regression payload tests | Fixed / browser tested |
| Admin berpotensi mengubah `owner_id` | Critical/High | Column grants + immutable identity trigger | Fixed in migration |
| Default/broad Data API grants | High | Revoke-all lalu regrant least privilege; role-safe RPC | Fixed in migration |
| Sale + initial payment tidak atomik | High | `create_sale_with_payment()` | Fixed in migration/frontend |
| Concurrent payment race | High | `record_payment()` + invoice row lock | Fixed in migration/frontend |
| Security Key tanpa lockout | High | 5 gagal → lock 15 menit | Fixed in migration/frontend |
| Password minimum terlalu rendah | Medium/High | Frontend min 8 + Auth hardening guide | Fixed frontend; Supabase setting required |
| Gudang menerima financial data berlebih | High | RPC masks HPP/price/total/payment; fulfilment-only UI | Fixed / browser tested |
| Stok bisa minus tanpa kontrol | Medium/High | Default OFF + DB-level enforcement + optional backorder | Fixed |
| Session token persistent di localStorage | High if XSS | Session moved to sessionStorage; legacy token removed | Fixed / browser tested |
| Supabase JS CDN floating | Medium | Dependency removed; secure polling used | Fixed |
| Missing CSP/security headers | Medium | CSP + Vercel/static host headers | Fixed in source |
| Service Worker dapat mencache request yang tidak seharusnya | High privacy/integrity | Same-origin app-shell-only cache policy | Fixed |
| Demo dapat disalahartikan sebagai secure storage | Medium | Visible production-data warning | Fixed |

## Database hardening

V1.8 migration menambahkan:
- immutable business ownership/system fields;
- immutable product/expense/member identity fields;
- `security_key_attempts`;
- role-aware product/sales RPC;
- atomic sales/payment RPCs;
- stock row locking and negative-stock rules;
- Security Key V2 lockout;
- least-privilege grants;
- revocation of legacy sensitive RPCs and direct sales mutation access.

## Frontend hardening

- Escaped dynamic business/user content.
- Warehouse-specific fulfilment views.
- Payment and sale mutation now use hardened RPCs.
- Session via sessionStorage.
- Password min 8.
- CAPTCHA-ready Turnstile integration.
- HTTP 429 friendly handling.
- CSP and security-header deployment files.
- No floating Supabase JS CDN dependency.
- Service worker restricts cache to app shell.

## QA evidence

### Real Chromium regression
**35 / 35 PASS** across two browser suites.

Coverage includes:
- stored-XSS execution prevention;
- malicious payload rendering in business/product/customer/expense;
- Invoice/Surat Jalan output encoding;
- mobile 390px tables/cards;
- Warehouse financial hiding;
- session localStorage → sessionStorage migration;
- payment history recalculation;
- paid status;
- negative-stock default.

### Static/source QA
See `STATIC_SECURITY_QA.md`.

## Not yet proven

The SQL migration has **not** been executed against the user’s real Supabase project from this build environment. Therefore the following remain a deployment gate, not a finished claim:
- PostgreSQL function compilation on that exact project/version;
- role/RLS integration against real Auth users;
- concurrency across real multi-device network requests;
- Supabase Auth CAPTCHA/password project configuration;
- response headers on the chosen production hosting platform.
