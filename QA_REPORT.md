# BizControl Online V1.7 — QA Report

Tanggal build: 10 Agustus 2026
Status: **Beta Candidate / Production Foundations implemented**

## Ringkasan

V1.7 menyelesaikan fondasi kode untuk role user, sinkronisasi cloud/realtime, backup/export, nomor dokumen production, error handling, dan paket user testing.

## Automated / Static QA

Hasil terakhir: **69 / 69 checks PASS**.

Yang diperiksa antara lain:

- JavaScript syntax (`node --check`).
- ID HTML statis tidak duplikat.
- Semua literal `data-action` memiliki handler.
- Tidak ada function declaration JavaScript yang duplikat.
- Role Owner/Admin/Kasir/Finance/Gudang/Staff tersedia.
- Role Gudang memakai flow update stok terbatas.
- Gate permission export aktif.
- `client_request_id`, stable request ID, timeout, session refresh, polling, dan Realtime marker tersedia.
- Backup JSON dan CSV export tersedia.
- SQL nomor Invoice/Kwitansi/Surat Jalan, unique index, dan sequence initialization tersedia.
- RLS/role functions, secure delete, warehouse DB guard, sensitive-field safe RPC, server-side financial calculation tersedia.
- Fresh schema sudah mengandung migration V1.7 final.

Output detail dapat direproduksi dengan:

```bash
python tests/static_check.py
```

## Local Browser QA

Hasil terakhir: **21 / 21 scenarios PASS** menggunakan Chromium headless pada UI aktual.

Skenario yang lulus:

- Dashboard Owner boot tanpa page error.
- Owner melihat Audit Log.
- Kasir tidak melihat Biaya/Laporan/Audit/Tim.
- Kasir tidak melihat HPP pada Produk.
- Kasir tidak mendapat tombol Export CSV pada Produk.
- Gudang mendapat aksi `Update Stok`.
- Modal Gudang hanya berisi stok/min stok; HPP dan harga tidak dapat diedit.
- Form Penjualan membuat tepat satu transaksi.
- Nomor lokal baru berformat `INV-YYYY-######`.
- Surat Jalan berformat `SJ-YYYY-######`.
- Transaksi Tempo dapat mulai dari belum dibayar.
- Pembayaran dapat ditambahkan ke invoice.
- Kwitansi berformat `KWT-YYYY-######`.
- Finance melihat Biaya dan Laporan tetapi tidak Audit.
- Admin melihat Audit.
- Modal mobile 390×844 muat di viewport dan tombol aksi tetap terlihat.
- Tidak ada JavaScript page error selama skenario pengujian.

Output detail dapat direproduksi dengan:

```bash
python tests/browser_local_check.py
```

## Security / Integrity hardening V1.7

- HPP produk dan HPP/laba transaksi pada Cloud tidak lagi mengandalkan UI hiding saja.
- Direct SELECT field sensitif dibatasi dan pembacaan dilakukan melalui RPC role-aware.
- Perhitungan data finansial penjualan divalidasi ulang di database.
- `paid_amount` invoice hanya boleh berubah melalui Riwayat Pembayaran.
- Nomor Invoice/Kwitansi/Surat Jalan tidak dapat diganti setelah record dibuat.
- Role Gudang dibatasi database-level untuk hanya mengubah `stock`/`min_stock`.
- Realtime client mendengarkan `sync_events` non-sensitif, bukan payload tabel finansial mentah.
- Delete permanen tetap melalui Security Key + secure RPC dan dibatasi Owner/Admin.

## Yang belum dapat dinyatakan PASS dari environment build ini

### 1. Live Supabase migration
Migration SQL sudah dibuat dan diperiksa secara statis, tetapi belum dijalankan pada project Supabase milik pengguna dari environment ini.

**Wajib diuji setelah deployment:** migration success, RLS aktual, role RPC, Realtime, dan secure delete terhadap database nyata.

### 2. Live multi-device sync
Kode Realtime + polling fallback sudah tersedia, tetapi test HP → Supabase → laptop membutuhkan project Supabase aktif dan dua sesi/perangkat nyata.

### 3. Concurrency nomor dokumen di database nyata
`next_document_number()` memakai operasi database atomik dan unique index, tetapi uji dua client serentak tetap harus dilakukan pada Supabase deployment sebenarnya.

### 4. Testing 5–10 UMKM nyata
Tidak dilakukan secara otomatis atau direkayasa. Folder release menyediakan `BETA_TEST_PLAN.md`, tracker, feedback template, dan production checklist untuk testing nyata.

## Release decision

**Layak:** internal testing + closed beta 5–10 UMKM.

**Belum disarankan:** open public paid SaaS dengan banyak customer sebelum checklist Cloud dan user beta di atas selesai.

Gate untuk launch berbayar:

1. Migration live berhasil.
2. Role/RLS diuji dengan minimal Owner + Kasir + Gudang + Finance.
3. HP ↔ laptop sync lulus.
4. Double-submit/retry tidak membuat transaksi ganda.
5. Nomor dokumen concurrency lulus.
6. Minimal 5 UMKM beta mencoba.
7. Critical bug = 0.
