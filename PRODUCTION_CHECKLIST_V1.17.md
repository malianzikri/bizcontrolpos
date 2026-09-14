# BizControl Online V1.17 — Production Checklist

Gunakan checklist ini pada **staging** sebelum memindahkan V1.17 ke production.

## 1. Database & deployment
- [ ] Backup database Supabase sebelum migration.
- [ ] Pastikan migration V1.9 Purchasing sudah diterapkan bila modul Pembelian dipakai.
- [ ] Pastikan migration V1.10–V1.16 sudah diterapkan tanpa error.
- [ ] Jalankan `migration-v1.17-production-readiness.sql` sekali pada project BizControl yang benar.
- [ ] Pastikan existing business tetap Active/Business setelah migration.
- [ ] Redeploy Edge Function `account-admin` dari `account-admin-edge-function.ts` V1.17.
- [ ] Pastikan secrets Edge Function tetap terpasang.
- [ ] Deploy source V1.17 ke Vercel.
- [ ] Hard refresh / clear PWA cache pada device test.

## 2. Subscription enforcement
- [ ] Admin Sistem dapat melihat daftar subscription.
- [ ] Admin Sistem dapat mengubah plan/status/period end/grace period.
- [ ] Active business dapat checkout dan melakukan mutation normal.
- [ ] Trial business dapat checkout selama trial aktif.
- [ ] Grace business masih mendapat akses write selama grace yang berlaku.
- [ ] Expired business tetap dapat login, membaca laporan dan export backup.
- [ ] Expired business tidak dapat checkout, edit stok, PO, biaya, refund, recipe, atau mengubah member.
- [ ] Suspended business bersifat read-only.
- [ ] Owner Cloud tidak dapat membuat bisnis kedua untuk memperoleh trial baru.

## 3. Offline / reliability
- [ ] Putus internet saat POS terbuka menampilkan banner Offline.
- [ ] Checkout dan semua cloud mutation diblokir saat offline.
- [ ] Sambungkan kembali internet dan reload/sync data berhasil.
- [ ] Tidak ada offline transaction queue yang dapat membuat invoice/stok ganda.

## 4. Onboarding & hardware
- [ ] Owner/Admin melihat checklist onboarding.
- [ ] Profil usaha dapat diselesaikan.
- [ ] Produk pertama terdeteksi selesai.
- [ ] Printer test 80mm membuka preview/print dengan benar.
- [ ] Test printer thermal 58mm dan 80mm nyata minimal satu unit masing-masing bila akan didukung resmi.
- [ ] Test barcode scanner USB/keyboard pada POS.

## 5. Backup & monitoring
- [ ] Export Backup JSON berhasil dan file dapat dibuka.
- [ ] Verifikasi File Backup menunjukkan business/version/count yang sesuai tanpa menulis data.
- [ ] `backup_events` mencatat export/verify pada Cloud.
- [ ] Error staging yang aman muncul di `app_events` / System Health.
- [ ] Tidak ada password, access token, refresh token, service-role key, atau data sensitif customer di telemetry.
- [ ] Prosedur restore database Supabase sudah didokumentasikan dan pernah diuji pada staging/clone sebelum go-live.

## 6. Role smoke test
- [ ] Owner: full business access + subscription status terlihat.
- [ ] Admin: operasional/finansial sesuai matrix, tanpa kelola anggota Owner-only.
- [ ] Kasir: POS/shift/member; tanpa HPP/report/refund/edit transaksi selesai.
- [ ] Finance: tanpa POS; laporan/pembelian/biaya/pembayaran sesuai akses.
- [ ] Gudang: stok/opname/recipe/penerimaan/pengiriman tanpa harga/HPP/nilai PO.
- [ ] Staff: dashboard dasar + produk read-only.

## 7. Go-live gate
Production boleh dipromosikan sebagai V1.17 setelah seluruh item kritis di atas PASS pada staging dan tidak ada issue Critical/High terbuka.
