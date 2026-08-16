# BizControl Online V1.8.1 — Production Patch Report

## Status
**Production Candidate / Supabase Staging Candidate**

Patch ini dibuat setelah review V1.8 menemukan satu celah high-impact: mutation RPC dapat mengembalikan seluruh row `sales`, sehingga HPP (`unit_cost`) dan `gross_profit` berpotensi terlihat dari Network response walaupun UI Kasir menyembunyikannya.

## Temuan yang ditutup

### HIGH — HPP leakage melalui mutation RPC
**Sebelum:** response `create_sale_with_payment()` / `update_sale_secure()` menggunakan serialisasi row sale lengkap.

**Sesudah:** response dibangun dengan allowlist field dan tidak pernah memasukkan:
- `unit_cost`
- `gross_profit`

Data setelah mutasi diambil ulang menggunakan `list_sales_for_business()` yang role-aware.

### MEDIUM — Future object privilege exposure
Default privileges pada schema `public` sekarang dicabut untuk browser roles. Object baru harus di-grant secara eksplisit.

### MEDIUM — SECURITY DEFINER search path
Function sensitif diberi fixed trusted search path. Browser role juga kehilangan CREATE pada schema public.

### PRODUCT GAP — Password recovery
Forgot Password + Reset Password telah ditambahkan. Recovery response bersifat generik agar tidak melakukan email/user enumeration.

## Regression yang dipertahankan dari V1.8
- Stored XSS escaping.
- owner_id/business_id/system fields guard.
- RLS + granular grants.
- Security Key 5 gagal → lock 15 menit.
- atomic create sale + initial payment.
- row lock untuk payment.
- negative stock default OFF.
- Warehouse financial masking.
- sessionStorage untuk cloud session.
- CSP/security headers.
- API/Auth response tidak dicache service worker.
- mobile responsive card.

## QA
- Static/source: **54/54 PASS**.
- Browser regression: **24/24 PASS**.
- `node --check app.js`: **PASS**.

## Residual / belum dapat divalidasi lokal
Patch SQL belum dijalankan pada project Supabase user. Karena itu hal berikut masih wajib dibuktikan di staging:
- migration berjalan tanpa error terhadap schema aktual;
- RLS/grants efektif pada JWT user nyata;
- Kasir tidak dapat memperoleh HPP melalui list maupun mutation RPC;
- Admin tidak dapat mengambil alih owner;
- Gudang tidak memperoleh data finansial;
- concurrent sale/payment pada dua perangkat tetap konsisten;
- recovery email benar-benar terkirim melalui SMTP dan redirect kembali ke aplikasi;
- CAPTCHA aktif pada sisi Supabase jika digunakan;
- backup/restore procedure teruji.

## Keputusan release
**Layak masuk staging dan closed beta setelah staging validation PASS.**

Belum disarankan mengklaim “100% aman” atau melakukan public SaaS launch sebelum pengujian database/auth nyata selesai.
