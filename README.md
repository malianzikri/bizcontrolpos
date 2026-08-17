# BizControl Online V1.8.1 — Production Patch

V1.8.1 adalah patch production/security di atas V1.8. Fokusnya menutup sisa celah sebelum aplikasi dibawa ke Supabase staging dan diuji sebagai production candidate. Tidak ada penambahan modul bisnis besar.

## Perubahan utama V1.8.1

### 1. Response RPC penjualan tidak membocorkan HPP
`create_sale_with_payment()` dan `update_sale_secure()` sekarang hanya mengembalikan field transaksi yang aman untuk client. Response mutasi tidak menyertakan `unit_cost` maupun `gross_profit`, termasuk ketika request dilakukan oleh Kasir melalui Network/API.

Setelah mutasi, aplikasi tetap reload data melalui `list_sales_for_business()`, yang melakukan masking berdasarkan role.

### 2. Default privilege database dibuat opt-in
Migration V1.8.1:
- mencabut `CREATE` schema `public` dari browser roles;
- mencabut default SELECT/INSERT/UPDATE/DELETE untuk future table;
- mencabut default EXECUTE untuk future function;
- mencabut default USAGE/SELECT untuk future sequence;
- me-reset EXECUTE pada function existing lalu hanya meng-grant RPC yang memang dibutuhkan aplikasi.

Tujuannya agar function/table baru tidak otomatis menjadi bagian Data API tanpa keputusan eksplisit.

### 3. SECURITY DEFINER diperketat
Function sensitif memakai fixed trusted `search_path`:

```text
pg_catalog, public, auth, extensions
```

Browser roles juga tidak memiliki `CREATE` pada `public`, sehingga tidak dapat menaruh object shadow di schema tersebut.

### 4. Forgot Password / Reset Password
Login sekarang memiliki alur:
1. `Lupa password?`
2. user memasukkan email;
3. aplikasi memanggil endpoint recovery Supabase;
4. pesan sukses selalu generik agar tidak mengungkap apakah email terdaftar;
5. link recovery kembali ke aplikasi;
6. user membuat password baru minimal 8 karakter;
7. recovery session diakhiri dan user harus login kembali.

### 5. Runtime config production
Konfigurasi public frontend dapat diletakkan di `runtime-config.js`:

```js
window.BIZCONTROL_CONFIG = {
  supabaseUrl: 'https://PROJECT.supabase.co',
  publishableKey: 'PUBLISHABLE_OR_ANON_KEY',
  turnstileSiteKey: 'OPTIONAL_TURNSTILE_SITE_KEY'
};
```

**Jangan pernah** memasukkan `service_role`/secret key ke file frontend.

`runtime-config.js` diset `Cache-Control: no-store` melalui `_headers` dan `vercel.json`.

## Upgrade database

### Sudah menggunakan V1.8
Jalankan pada **Supabase staging terlebih dahulu**:

```text
migration-v1.8.1-production-patch.sql
```

### Project baru
Gunakan:

```text
supabase-schema-v1.8.1.sql
```

atau:

```text
supabase-schema.sql
```

## Setup Auth sebelum staging/public release

Di Supabase Dashboard:
- set Site URL ke URL aplikasi staging/production;
- masukkan URL aplikasi ke Redirect URLs;
- gunakan password policy minimal 8 karakter atau lebih kuat;
- aktifkan CAPTCHA server-side jika Turnstile dipakai;
- gunakan SMTP yang sesuai untuk email production/recovery;
- pastikan publishable/anon key saja yang berada pada frontend.

## QA V1.8.1

### Static/source QA
**54/54 PASS**

Meliputi:
- JS syntax;
- default privilege hardening;
- explicit EXECUTE grants;
- tidak ada HPP/gross profit pada response mutasi;
- role masking Kasir/Gudang;
- auth recovery;
- sessionStorage;
- CSP/header;
- atomic sales/payment;
- Security Key lockout;
- mobile responsive card tetap ada.

### Browser regression QA
**24/24 PASS** pada Chromium harness.

Meliputi:
- app boot;
- Forgot Password UI;
- recovery request;
- generic recovery response;
- update password + logout recovery session;
- mobile Kasir 390px tanpa horizontal overflow;
- responsive card/action;
- stored-XSS regression nama bisnis;
- tidak ada uncaught runtime exception pada skenario pengujian.

## Status release

V1.8.1 adalah **Production Candidate untuk staging**, bukan bukti bahwa database production user sudah aman. Migration belum dieksekusi dari environment ini pada project Supabase milik user.

Sebelum public launch, lakukan:
1. backup staging/production;
2. apply migration ke staging;
3. buat akun Owner/Admin/Kasir/Finance/Gudang nyata;
4. uji direct RPC sebagai Kasir dan pastikan tidak ada `unit_cost`/`gross_profit`;
5. uji transaksi/pembayaran simultan minimal 2 device;
6. uji email Forgot Password dari awal sampai login ulang;
7. cek Security Advisor dan log database;
8. closed beta 5–10 UMKM;
9. hanya deploy production setelah tidak ada Critical/High issue.

Lihat `PRODUCTION_PATCH_REPORT.md` dan `STAGING_VALIDATION_CHECKLIST.md`.

## V1.8.2 Staging Fix
Pembuatan bisnis Cloud sekarang melalui RPC `create_business(p_name)`. `owner_id` selalu diambil dari `auth.uid()` di database dan tidak lagi dikirim dari browser. Jalankan `migration-v1.8.2-staging-business-create.sql` pada staging V1.8.1 sebelum menggunakan source ini.


## V1.8.3 Staging Read Fix
- Frontend memanggil `list_products_for_business(p_bid)` dengan nama parameter yang sesuai database V1.8/V1.8.1 staging.
- Error pembacaan produk tidak lagi diubah diam-diam menjadi array kosong.
- Tidak membutuhkan migration SQL baru jika staging sudah menjalankan RESUME V2 + migration V1.8.2.


### Staging DB hotfix: document numbering
If staging shows `column reference "doc_type" is ambiguous` while saving a sale, run `migration-v1.8.3-doc-type-hotfix.sql`. The fix keeps the function signature unchanged, removes PL/pgSQL name ambiguity, and keeps the document-number helper non-callable by browser roles.

## V1.8.4 Team Invitation

- Owner now invites employees directly from **Tim & Role**; employees no longer need to self-register first.
- New accounts receive a Supabase Auth invitation email and create their password from the invite link.
- Existing accounts are attached directly to the business with the selected role.
- Membership has `pending` / `active` status.
- Owner can **Hapus / Cabut Akses**. Removing the membership immediately removes database access through RLS.
- Invited employee accounts with no active business cannot auto-create an Owner business.
- The invitation operation is handled by the server-side `team-invite` Edge Function so the browser never receives a service-role/secret key.

See `TEAM_INVITATION_SETUP.md` and run `migration-v1.8.4-team-invitation.sql` before testing Cloud mode.


## V1.8.5 Production Final UX

- Supabase/Cloud URL and Publishable Key are deployment-managed only; there is no Owner UI to view/change them.
- Legacy `bc_cloud_config` saved by older builds is removed on boot.
- First visit without a session opens the Login/Daftar landing instead of silently entering Demo.
- `Coba Demo Gratis` opens a local sandbox without authentication and never writes demo data to Supabase.
- Demo includes a visible `Masuk / Daftar` path back to Cloud accounts and a one-click Reset Data Demo.
- Logout returns to the account landing page.
- Publishable keys remain visible to browser developer tools by design; authorization continues to be enforced by RLS/RPC. Never place a service-role/secret key in runtime config.


## V1.8.6 Multi-Item Cashier

- Tombol **Keluar** dipindahkan dari Pengaturan ke topbar akun agar lebih cepat dijangkau, termasuk di mobile Cloud mode.
- Satu transaksi Kasir sekarang merupakan satu **invoice dengan keranjang multi-item**. User dapat menambahkan beberapa produk/jasa, mengubah qty, dan menghapus baris sebelum menyimpan.
- Diskon tetap berada di level invoice. Pembayaran, riwayat cicilan, kwitansi, dan status Lunas/Belum Lunas tetap berada pada satu invoice.
- Invoice dan Surat Jalan mencetak seluruh item pada transaksi; Surat Jalan tetap tidak menampilkan harga.
- Cloud menambahkan tabel `sale_items` dan RPC multi-item. Stok diproses per item dengan row locking dan validasi stok.
- Existing invoice satu-barang otomatis di-backfill menjadi satu `sale_items` ketika migration dijalankan; stok lama tidak dikurangi ulang.
- Backup JSON sekarang menyertakan `saleItems`; Export Semua CSV juga mengekspor detail item penjualan.
- Role masking tetap berlaku: Kasir/Gudang tidak memperoleh HPP item dari RPC list item.

### Upgrade staging V1.8.5 → V1.8.6

1. Backup database staging terlebih dahulu.
2. Jalankan `migration-v1.8.6-multi-item-cashier.sql` sekali di Supabase SQL Editor.
3. Deploy frontend V1.8.6 ke Vercel/GitHub. `runtime-config.js` tetap memakai Project URL + Publishable Key yang sama.
4. Edge Function `team-invite` tidak perlu diubah.
5. Test minimal: satu invoice 2–3 barang, edit qty, transaksi tempo, cicilan, hapus invoice dan pastikan stok kembali, Invoice, Kwitansi, Surat Jalan, serta Owner/Kasir dari dua perangkat.

Migration ini mengubah model transaksi dan **wajib** dijalankan sebelum frontend V1.8.6 dipakai pada Cloud mode.

## V1.8.7 Invite-Only Access & Password Control

- Pendaftaran Owner publik dihapus dari UI. Halaman publik hanya menyediakan **Masuk**, **Lupa Password**, **Chat Admin untuk Daftar**, dan **Coba Demo Gratis**.
- Demo mobile memiliki tombol **Masuk** langsung di topbar, jadi user tidak perlu masuk ke Pengaturan.
- Owner baru diprovision oleh **Admin Sistem** melalui Edge Function `account-admin`; akun Auth biasa tidak dapat membuat bisnis sendiri.
- Migration menambahkan `owner_accounts` dan meng-hardening RPC `create_business()` agar hanya Owner terkelola/existing Owner yang boleh membuat bisnis.
- Semua user Cloud dapat mengganti password sendiri dari Pengaturan → **Akun & Password**.
- Owner dapat mengirim link reset password untuk karyawan aktif dari **Tim & Role**.
- Admin Sistem dapat mengundang Owner baru serta mengirim link reset password Owner dari menu **Admin Sistem**.
- Hak Admin Sistem diverifikasi server-side melalui secret `BIZCONTROL_SYSTEM_ADMIN_EMAILS`; memunculkan menu secara paksa di DevTools tidak memberikan hak server.
- Nomor WhatsApp pendaftaran dikelola di `runtime-config.js` melalui `supportWhatsApp` dan tidak dapat diedit dari UI customer.

### Upgrade V1.8.6 → V1.8.7

1. Backup database.
2. Jalankan `migration-v1.8.7-invite-only-access.sql`.
3. Buat/deploy Edge Function `account-admin` dari `account-admin-edge-function.ts`.
4. Set Edge Function secrets `BIZCONTROL_SYSTEM_ADMIN_EMAILS` dan `BIZCONTROL_ALLOWED_REDIRECTS`.
5. Di Supabase Auth, matikan **Allow new users to sign up** agar Auth project juga invite-only.
6. Deploy frontend V1.8.7 dan hard refresh.
7. Test: Demo mobile → Masuk, Chat Admin, undang Owner, login Owner pertama, ganti password sendiri, reset karyawan oleh Owner, reset Owner oleh Admin Sistem, lalu pastikan user biasa tidak dapat membuat bisnis melalui RPC.

Lihat `V1.8.7_SETUP.md` untuk langkah deployment detail.


## V1.8.8 Period & Annual Reports
- Kasir: filter Bulan atau rentang Dari tanggal–Sampai tanggal.
- Export Penjualan CSV mengikuti periode filter.
- Biaya: filter Bulan atau rentang Dari tanggal–Sampai tanggal.
- Total dan Export Biaya CSV mengikuti periode filter.
- Laporan Laba Rugi dapat diganti per bulan.
- Ringkasan Periode mengikuti bulan pilihan.
- Tren laporan menjadi 12 bulan Januari–Desember dan tahun dapat diganti.
- Export Tren 12 Bulan CSV.
- Layout filter dan tabel sudah disesuaikan untuk mobile.
- Tidak membutuhkan migration SQL baru.
